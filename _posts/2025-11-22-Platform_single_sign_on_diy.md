---
title: Platform Single Sign-on DIY
date:   2025-11-22 14:30:23 +0100
categories: technology
layout: post
comments: true
tags:  keycloak idp apple
---

### What?

This is a post about how to implement [Platform Single Sign-on](https://support.apple.com/en-vn/guide/deployment/dep7bbb05313/web), Apple’s framework for simplifying logins from macOS devices. It builds upon the [SSO Extensions](https://support.apple.com/en-vn/guide/deployment/depfdbf18f55/web), but takes it a bit further. But it is also a collection of thoughts.

Why, you ask? The reason is pretty simple: it is almost impossible to find a piece of documentation where we can understand clearly what is it that Apple want IdPs to implement. The only exception to my impression on this is the [excellent article](https://twocanoes.com/psso-technical-deep-dive/) written by Timothy Perfitt from [Twocanoes](https://twocanoes.com) on the subject. Timothy also wrote a very popular example on [how to implement a simple Platform SSO server.](https://github.com/twocanoes/psso-server-go/tree/main). 
I plan not to repeat what Timothy wrote on his [series of articles](https://twocanoes.com/sso/) about Platform SSO. I’d rather go a bit further and discuss ideas and design possibilities, as well as what I consider lacking.

### Disclaimers

My opinions are mine and mine only, and do not by any means reflect those of my employer.

Everything written here is based on using shared keys from the Secure Enclave. Other authentication methods, such as using Passwords or smartcards are not covered.

### Implementing Platform SSO from the perspective of an IdP

The rumour goes that Platform SSO hasn’t really become popular. The only two known implementations took a few years to became available, and those are basically Microsoft’s and Okta’s. It is difficult to speculate why this happened, but I have a few theories:

- **Lack of MDM native support**: Platform SSO (PSSO from now on) is basically IdP-centric. Besides configuring Platform SSO and having the possibility to integrate device registration with MDM’s, its implementation requires IdP-compatibility and tight cooperation between Mac admins and teams responsible for authentication;
- **Substantial implementation of API’s on IdPs**: PSSO requires some APIs that need to be implemented on IdPs.  This basically requires that every IdP needs to come up with its own implementation. 
- **Scarce documentation and examples**: This is probably debatable. There _is_ [documentation on how to implement PSSO](https://developer.apple.com/documentation/authenticationservices/authentication-process), it there is little documentation with code examples and possible pattern flows. Or, in other words, sometimes it is hard to understand what Apple is thinking or how they want IdPs to implement this.
- **Passkeys**: One could simply ask: why go through this hassle if the IdP could simply support Passkeys and call it a day? While Platform SSO gives macOS users the best possible experience, as well as giving IdP admins good tools to manage sessions, Passkeys are almost as easy to use, without having to implement a whole set of APIs to support just macOS devices.

Nevertheless, PSSO is a great addition to any IdP who wants to offer an unbeatable user experience for macOS users. 
The organization I work for has (through me :) developed a [Platform Single Sign-on extension](https://github.com/unioslo/keycloak-psso-extension) for [Keycloak](https://www.keycloak.org), an open-source IdP and IAM that is quite popular. Keycloak is incredibly expandable, and could easily be extended to support PSSO. 

### Requirements for IdPs and how we did it

Before we dive into what IdPs need to offer Platform SSO, it is important to distinguish an SSO Extension to a Platform SSO Extension. Both will be on the same package, but one can develop an SSO Extension without support for Platform SSO. 
What does an SSO Extension does? Well, it basically intercepts any call to a configurable URL (the configuration needs to be managed by an MDM) so that you can add some logic of how to authenticate the user, so that other applications/websites can reuse that authentication.
On the [example provided by Twocanoes](https://twocanoes.com/building-a-single-sign-on-extension-on-macos/), that logic, for example, is simply saving cookies the IdP sets into the Keychain, so that they are sent back to whatever attempts to authenticate again.  With PSSO we might want to do things a bit differently, but the point is that there’s no recipe of what an SSO Extension should do - it needs to be implemented according to the logic of the IdP. Cookies are possibly the most common pattern here, so it makes sense to use them in this context.
On an SSO Extension, everytime an application or Safari hits a predefined point, the `beginAuthorization`method of your extension, and from here on you are free to do whatever you want: present a login screen if the user isn’t authenticated, send back some cookies, etc.
But Platform SSO takes this further: it fetches tokens from the IdP on behalf of the user so that they can be used by the SSO Extension to authenticate the user.
Let’s suppose your IdP does a standard OIDC flow.  Platform SSO doesn’t change that, and you can develop your SSO to cope with that OIDC flow. What Platform SSO introduces is the possibility of registering the device and the user on the IdP so that the SSO Extension can use that token as a _credential_ for the user, instead of simply presenting a login screen.  The idea is that when the abovementioned `beginAuthorization`method is called on your SSO Extension, you inject that credential (or make it available for the IdP as a cookie, for example - I wouldn’t do that, but it is possible) into the request, and your IdP will evaluate it, the same way it evaluates a password, a MFA credential, etc.

So, what do you need to implement, basically, to provide PSSO on your IdP? Well, here’s the answer, but notice that there are many ways to Rome:

Custom endpoints (Apple doesn’t really tell you how you create these, and is not so opinionated about it):
- an endpoint to register the device (called _Device registration_ by Apple)
- an endpoint to register the user (called _User registration_), which is basically to create some sort of credential for the user based on his key - more about keys later

Endpoints that conforms to Apple’s expectations:
- an endpoint to request a `nonce` value to be used during logins. 
- an endpoint to request tokens, which is basically an endpoint where you send a _[login request](https://developer.apple.com/documentation/authenticationservices/creating-and-validating-a-login-request)_ and obtain a _[login response](https://developer.apple.com/documentation/authenticationservices/creating-a-json-web-encryption-jwe-login-response)_.  A _login request_ and a _login response_ could probably be best described as _credential request_ and _credential response_, or, maybe, _token request_ or _token response_. Don’t think of this as logging in the user (you do that on the SSO extension). Here, you simply obtain credentials to log that user in later on the SSO Extension.

Besides these endpoints, you need to come up with a way to recognize these tokens when the user authenticates via the SSO extension. More on that later.

On Keycloak, we also created a client. It isn’t confidential, but uses PKCE with SHA256, and it needs to have the `urn:apple:platformsso`  scope.
This client is used by the SSO extension in two ways:

-  to authenticate the user for device and/or user registration (but we don’t _have_ to - this depends on how you want to associate the user and the IdP, and what checks you make to allow device registration as well. Our Keycloak extension expects a token from this client;
- as a part of macOS own token retrieval process.

On our Weblogin SSO Extension, as well as on Keycloak, we used a hardcoded name for the client, so when you create yours, name it _psso_. In the future, we will make this configurable.


### Requirements for your PSSO Extension

Well, the PSSO Extension is basically an implementation of the `ASAuthorizationProviderExtensionRegistrationHandler` and its methods. The main ones are:

- `beginDeviceRegistration`
- `beginUserRegistration`

Their implementation is quite similar. What you want to do here is to:
- fetch some keys from the Secure Enclave (their public keys, mind you)
- send them to the IdP for registration
- Implement some logic for authentication

The extension needs to be configured with a profile managed by your MDM. This profile is - but doesn’t have to me - made up of multiple payloads:

- One for your SSO Extension, including the Platform Extension configuration
- another for the preferences of your application. Here you can save thing you will need on the app, like the URL of your IdP, the client ID, etc.

It needs to be configured by your MDM. This configuration will look like this: 

```
<plist version=«1.0»>
  <dict>
    <key>PayloadContent</key>
    <array>
      <dict>
        <key>BaseURL</key>
        <string>https://<YOURINSTANCE>/realms/<YOURREALM>/</string>
        <key>Issuer</key>
        <string>https://<YOURINSTANCE>/</string>
        <key>Audience</key>
        <string>psso</string>
        <key>ClientID</key>
        <string>psso</string>
        <key>PayloadDisplayName</key>
        <string>Weblogin SSOE</string>
        <key>PayloadIdentifier</key>
        <string>mdscentral.00A38C42-503B-4016-A86D-2186CDA5989C.no.uio.WebloginSSO.3E7FAF27-6179-46AA-B1A3-B55E08D3273D</string>
        <key>PayloadOrganization</key>
        <string></string>
        <key>PayloadType</key>
        <string>no.uio.WebloginSSO.ssoe</string>
        <key>PayloadUUID</key>
        <string>3F7FDF27-6179-46AA-B1A3-B55E08D3273D</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
      </dict>
      <dict>
        <key>PayloadDisplayName</key>
        <string>Weblogin Platform SSO</string>
        <key>PayloadIdentifier</key>
        <string>mdscentral.00A38C42-503B-4016-A86D-2186CDA5989C</string>
        <key>PayloadOrganization</key>
        <string></string>
        <key>PayloadScope</key>
        <string>System</string>
        <key>PayloadType</key>
        <string>Configuration</string>
        <key>PayloadUUID</key>
        <string>851A1B46-6A8A-442B-91CB-BC12FF416766</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
      </dict>
      <dict>
        <key>AuthenticationMethod</key>
        <string>UserSecureEnclaveKey</string>
        <key>ExtensionIdentifier</key>
        <string>no.uio.WebloginSSO.ssoe</string>
        <key>PayloadDisplayName</key>
        <string>Weblogin SSO</string>
        <key>PayloadIdentifier</key>
        <string>com.apple.extensiblesso.CA351D35-96B1-41CF-B25B-DF3273189AAD</string>
        <key>PayloadOrganization</key>
        <string></string>
        <key>PayloadType</key>
        <string>com.apple.extensiblesso</string>
        <key>PayloadUUID</key>
        <string>4B7148CD-1069-4140-95CE-78F61BCD9C2B</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
        <key>URLs</key>
        <array>
          <string>https://<YOURINSTANCE>/realms/<YOURREALM>/protocol/</string>
          <string>https://YOURINSTANCE/realms/<YOURREALM>/psso</string>
        </array>
        <key>PlatformSSO</key>
        <dict>
          <key>AccountDisplayName</key>
          <string>Universitet i Oslo - Weblogin</string>
          <key>AuthenticationMethod</key>
          <string>UserSecureEnclaveKey</string>
          <key>EnableAuthorization</key>
          <true />
          <key>EnableCreateUserAtLogin</key>
          <true />
          <key>NewUserAuthorizationMode</key>
          <string>Groups</string>
          <key>UseSharedDeviceKeys</key>
          <true />
          <key>UserAuthorizationMode</key>
          <string>Groups</string>
          <key>AllowDeviceIdentifiersInAttestation</key>
          <true />
        </dict>
        <key>TeamIdentifier</key>
        <string>YOURTEAM</string>
        <key>Type</key>
        <string>Redirect</string>
      </dict>
    </array>
    <key>PayloadDescription</key>
    <string></string>
    <key>PayloadDisplayName</key>
    <string>Weblogin Platform SSO test/V_41</string>
    <key>PayloadIdentifier</key>
    <string>37f5c3b4-36c6-101f-9485-90082e154a1a</string>
    <key>PayloadOrganization</key>
    <string></string>
    <key>PayloadRemovalDisallowed</key>
    <false />
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>dbacb344-7490-4948-b51a-b395d948fd54_41</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadScope</key>
    <string>System</string>
  </dict>
</plist>
 
```

### How  we did it on the IdP

So, I said already that Keycloak is easy to expand, right? So, what we did at first was to create the necessary endpoints. You can see their implementation on [our repo on github](https://github.com/unioslo/keycloak-psso-extension).  Note that this Keycloak extension still needs a few things to be production grade, and we’ll try to point out here what is missing.
All our endpoints are configured as a Keycloak resource. You can see all of them [here](https://github.com/unioslo/keycloak-psso-extension/blob/main/src/main/java/no/uio/keycloak/psso/PSSOResource.java).

You are free to give the endpoints any name you wish. On your PSSO Extension, you need to configure the token and the nonce endpoint, as well as the keys endpoint.

Notice that, for those endpoints where Apple requires a certain standard, you need to accept requests with a few characteristics. Fortunately, Apple tells you how requests should be formed. You can check the documentation, but it is easy to see the format using this command on your terminal: `app-sso  platform -m`, when developing your PSSO Extension.

#### The `nonce` endpoint:

Apple requires the `nonce` endpoint so that replay attacks can be avoided. So you need to implement some mechanism to receive these requests and return a value.  

How does the Mac send its `nonce` request? [According to the documentation:](https://developer.apple.com/documentation/authenticationservices/obtaining-a-server-nonce) 


```
POST /oauth2/token HTTP/1.1
Host: auth.example.com
Accept: application/json
Content-Type: application/x-www-form-urlencoded
client-request-id: DCAB01D3-B1FE-4E1C-802F-B3EBDCDF9E67
grant\_type=srvchallenge 
```


Send back a json containing a key with the `nonce` value. You can configure the name of that key on your PSSO Extension, otherwise `nonce`is used.

On our implementation, the endpoint is called `/nonce`.

#### The device registration endpoint

Here, you are free to do as you want. What do you want to do here? Basically, you want to receive the request with the device keys and persist them somewhere.
Here, you might also want to perform some sort of authentication., otherwise anyone could simple send certificates to your server.
Apple doesn’t really care how and if you do anything here. Their documentation gives some hints of what you should be doing, but they don’t dive deep into this.
They say you might want to use a `RegistrationToken`, which is something the MDM generates dynamically so that the IdP can use to actually check with the MDM if that device is legit, or you can use _device attestation_`.
Since our MDM (Workspace ONE) doesn’t really implement the `RegistrationToken`on its SSO Extension profile, we need to do it the hard way and implement device attestation. more on that later.

Our endpoint for device registration is called `/enroll`, and it accepts `POST`requests with a json with the following keys/values:
- `DeviceSigningKey`
- `DeviceEncryptionKey`
- `SignKeyID`
- `EncKeyID`
- `attestation`
- `nonce`
- `accessToken`

The `DeviceSigningKey`and the `DeviceEncryptionKey` are used to, well, sign and encrypt login requests and responses between the macOS device and the IdP. Their ID counterparts are used so that you can search for the keys on your database.

The `attestation`is a cryptographic token that is signed with the private key of your SigningKey (you can use another key here as well) that lives on your Secure Enclave. You can then check this against Apple’s root CA, which we include with our extension. You need to`AllowDeviceIdentifiersInAttestation` on your configuration profile so that you can extract the serial number and `deviceUDID`from the attestation. This is information that you can use as part of your device management workflows. Our extension requires this.

On our [Weblogin SSO Extension](https://github.com/unioslo/weblogin-mac-sso-extension), you can see how we generated the keys and the attestation on our `registerDevice()`method on this [file](https://github.com/unioslo/weblogin-mac-sso-extension/blob/main/ssoe/AuthenticationViewController.swift).

You need to send a `nonce` that you previously acquired via the `/nonce` endpoint.  

You also need to send authenticate the user and send their `accessToken`. You can also see on our extension how we ask the user to authenticate. You don’t really need to authenticate the user here, actually.  But since the extension doesn’t check, after the attestation,  if that device is "ours" with the MDM, we introduce this authentication - which you kinda need to do for the user anyway. Attestation tells us the device is legit, and that it is managed.  But it doesn’t prove it is managed by us.  

If you modify the extension, you might remove the accessToken verification and introduce some MDM check.

This was the only part of this Keycloak extension where we needed to use database storage. Fortunately, this wasn’t super hard to do with Keycloak.

#### The user registration endpoint

This endpoint is called `/enrolluser` and is very similar to the device registration. The keys we send are similar:

-  `nonce`
- `userKey`
- `userKeyId`
- `attestation`
- `accessToken`

What is super cool here is that Keycloak makes it very easy to save the user’s key as a _credential_. This allows both admins and users to revoke it on their admin and user GUI, respectively:

![User account console showing the Platform SSO credential](../../assets/2025/keycloak_psso_account.jpg)

Keycloak stores this as a `CredentialModel`. 
Here we do need the `accessToken` so that we can confirm the user registering the device really has an account. 
Again, on our companion SSO Extension you can see how we provide the keys and attestation.

#### The token endpoint

Next, we created the `/token` endpoint in order to receive the _login request_ and send back the _login response_. 

We created some classes to [validate the request](https://github.com/unioslo/keycloak-psso-extension/blob/main/src/main/java/no/uio/keycloak/psso/token/JWSDecoder.java) as [suggested by Apple](https://developer.apple.com/documentation/authenticationservices/creating-and-validating-a-login-request), and also to [build the response](https://github.com/unioslo/keycloak-psso-extension/blob/main/src/main/java/no/uio/keycloak/psso/token/JweBuilder.java) in a [format the macOS will accept](https://developer.apple.com/documentation/authenticationservices/creating-a-json-web-encryption-jwe-login-response).


So, the endpoints above is basically what you need to process Platform SSO requests from a Mac.  While the `/enroll` and `/enrolluser` are called by your extension when you decide that they should be called, the `/nonce` and `/token` endpoints need to be written according to Apple specifications. 

#### When does the PSSO extension call these endpoints?

So, as I said, you decide when to call the `/enroll` and `/enrolluser` endpoints. You might want to call them from your `beginDeviceRegistration` and `beginUserRegistration` respectively.  Everytime you start or repair your device registration, the first method is called, and when you register the user - either right after a device registration or later - the second method is called.

The `/token` method is called:
- when the user authenticates on his mac, by restarting the machine or unlocking it
- [by itself when the tokens have expired](https://developer.apple.com/documentation/authenticationservices/platform-single-sign-on-sso)

The _login response_ will include the `id_token`and a `refresh_token`, and here goes a very special rant from me:

When using an authentication method that is not the Secure Enclave key, the Platform SSO will call the `/token` endpoint and send the `refresh_token`
in order to get new, fresh `id_tokens`. But for some reason I don’t understand, it won’t do that with the Secure Enclave. Here is [Apple’s  explanation](https://developer.apple.com/documentation/authenticationservices/creating-a-refresh-request) for that: 

> A refresh request uses the previous refresh token to request a new token without prompting the user for credentials. The system attempts it when the existing token hasn’t expired and the time since the last full login hasn’t exceeded the LoginFrequency in the Device Management profile. It doesn’t apply to User Secure Enclave key authentication, _because the user isn’t prompted for credentials_.

I really don’t get it. What is Apple trying to say here? 

- Should I prompt the user for credentials with the Secure Enclave when the refresh token expires?
- Should we implement some logic on the PSSO extension to update that `id_token`? 

I really don’t understand why Apple renews the id token for other authentication methods except for the Secure Enclave.

This means that we need to either:
- renew the `id_token` ourselves, or
- disregard the `id_token` and simply use the `refresh_token` as an opaque credential.

Grudgingly, we went for the second.  We don’t use the `refresh_token` to refresh anything.  We just piggyback on its verifiability on Keycloak, as well as on its long lifetime. If Keycloak is configured to only allow the refresh token to be used once, this extension doesn’t work so well. Luckily, the default configuration of Keycloak is that the reuse of refresh tokens is allowed. 

We might need to revisit this in the future, but we really hope that Apple extends the automatic renewal of refresh tokens to Secure Enclave authentication. It makes more sense to use id tokens for authentication. 


#### The authentication itself

One thing that you need to keep in mind:

In common with the Platform SSO and the SSO Extensions is the `loginManager`, an instance of the `ASAuthorizationProviderExtensionLoginManager` protocol.  The `loginManager` has access to:

- the [loginConfiguration](https://developer.apple.com/documentation/authenticationservices/asauthorizationproviderextensionloginmanager/loginconfiguration), which is where the data regarding your idp, its endpoints, etc, is saved,
- the [userLoginConfiguration](https://developer.apple.com/documentation/authenticationservices/asauthorizationproviderextensionuserloginconfiguration), where you can save the username and other claims you need on each login request.
- the [ssoTokens](https://developer.apple.com/documentation/authenticationservices/asauthorizationproviderextensionloginmanager/ssotokens) - this is where you fetch the tokens you need on your `beginAuthorization` method of your SSO extension.

So, when the PSSO fetches the _login response_, it saves the `id_token`and the `refresh_token` on the `ssoTokens` member of the `loginManager`. That’s where you fetch them if you need them to authenticate the user at the IdP.

We developed an authenticator, which is how Keycloak calls the diverse methods to verify a user.  Keycloak comes with built-in authenticators, such as username/password, OTP, kerberos, passkeys, etc., and allows developers to code their own.

Our [authenticator](https://github.com/unioslo/keycloak-psso-extension/blob/main/src/main/java/no/uio/keycloak/psso/PSSOAuthenticator.java) inspects the header of the authentication requests and checks if a `Platform-SSO-Authorization` header is present. If so, we evaluate it and authenticate the user.

The token we send with the header is an encoded json in base64 format, with the following key/values:

- `refresh_token`
- `kid` (the Signing Key ID of the device, so that we find which key to use for verifying that this is a legit request)
- `signed_at` 
- `username` (doesn’t really work, it seems Apple doesn’t allow the explicit use of the saved [loginUserName](https://developer.apple.com/documentation/authenticationservices/asauthorizationproviderextensionuserloginconfiguration/loginusername)

Since we added the username to the refresh token, with this data the authenticator will be able to:
- check if the request came from a known device
- validate the refresh token using Keycloak’s own API
- consider the user authenticated
- attach all authentication results from the same device to the same session, which makes it easier to manage sessions (and the reason why we’d love Apple to allow automatic renewal of id tokens.

So our SSO Extension basically does this: 

- when triggered by a call to the `/protocol/openid-connect/auth`, the SSO extension injects the header with our token, as described above,
- if the response is not the callback with the value from the `redirect_uri` with a code, but rather a form with a password field, we display the login window.
- we return the the browser as soon as we get a redirect to the callback, which is always the `redirect_uri`.

It should work a bit the same way with SAML, except it doesn’t.  So, right now, our SAML flow is a bit erratic. If you can help us to fix it, we’d love to hear from you.

We don’t care about the cookies anymore, because if another application needs the cookies, they simply authenticate again and the extension will give them back with the response.  The SSO is performed by injecting the token into the request, not by keeping cookies. All in all, it will be the same session anyway.

### A few things that don’t work well  yet

There are a few things that need to be fixed:

- better handling of required actions: Keycloak has some required actions that, when called from their internal clients like the _Account console_, seems to create a reauthentication flow that don’t play ball well with our interception of the authentication url. It works perfectly now, but the required action is performed inside the SSO Extension, not on the browser. We’d like to get this done on the browser, but there’s a conflict with cookies that we can’t seem to solve.
- SAML, as pointed above,
- the implementation of some security checks during the authentication, the same way that Keycloak does when using their [CookieAuthenticator](https://github.com/keycloak/keycloak/blob/081d8e5a01aa84e04236a8de7adb573dd5c6cc0b/services/src/main/java/org/keycloak/authentication/authenticators/browser/CookieAuthenticator.java#L40). This will be done soon, but until then, if your Keycloak instance makes use of ACR/LoA, this authenticator might not comply with your authentication rules.

### Conclusion

We believe that this implementation might be helpful for a lot of people that want either to try Platform SSO or to provide Platform SSO without having to rely on one of the big IdPs. Theoretically, with a few modifications and by using [Token Exchange,](https://www.keycloak.org/securing-apps/token-exchange) , this solution can potentially be used in a way where Keycloak becomes a broker between Macs and other IdPs, but this is not something we tested or implemented.

It would be very nice if other developers could join our efforts, especially when it comes to the SSO Extension and its processing of SAML flows. If you can and want to help, send PR’s our way or drop as a line on the \#Keycloak channel at the MacAdmins [Slack](https://macadmins.slack.com/archives/C09UKEDGBEH) . 

Finally,  I just wish Apple could be a bit more explicit on how they believe this extension should be used:

- After a token expiration, should we renew automatically for the user (after all, the `loginManager` has a method for that,  or should the user authenticate manually?
- How should we handle SAML flows?
- Why no refreshing of tokens for Secure Enclave flows?

I think there’s a lot that could be accomplished here if some of Apple’s _intentions_ were known. But i must admit that, after implementing this extension, a lot of the documentation makes more sense - in the beginning, it felt insufficient, but I guess that’s mostly because there are no examples or design patterns shown anywhere, except by those examples from Twocanoes.

### Acknowledgments

We are very grateful to the work of Timothy Perfitt and Joel Rennich, who across presentations and articles made this subject a bit clearer to a lot of people, myself included.

I am also grateful to my colleagues Gaute and Thomas, who encouraged me to write this, and who came with good ideas and feedback along the way.