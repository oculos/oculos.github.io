---
title:  Using FreeIPA with FreeNAS
date:   2020-11-08 19:00:23 +0100
categories: personal
layout: post
comments: true
tags: freeipa ldap freenas 
---

I have long wanted to play a bit with LDAP, and got it working once on a Raspberry PI. When it finally worked, my SD card got corrupted and I lost all my hard work. 

I decided to play with [FreeIPA](https://freeipa.org), as it takes all the complexity of setting up LDAP and its security away from the user. I am really impressed by how easy was to setup FreeIPA and to use for authenticate users on other systems. 

I've now succesfully managed to use FreeIPA to provide user directory for both [FreeNAS](https://freenas.org) and [Nextcloud](https://nextcloud.com), though I will wait a bit to use it as my main source for authentication as it will take a bit of time to migrate my local users on those services to my directory ones.

I was surprised by the lack of guidance on how to use FreeIPA with FreeNAS, so I decided to write what I learned here after reading some forums and trying some stuff.

Before starting, it might be helpful to set your nameserver on FreeNAS to the one provided by FreeIPA.

## Configuring Kerberos

Start here, so you get things working. 

#### Configure the Kerberos Realm

- Click on `Directory Services`, then then choose `Kerberos Realms`
- Click on `Add`
- Type your REALM.
- I clicked on `Advanced Mode` and entered the kdc and Admin server, which basically are my FreeIPA server address.
- Save it

#### Configure the Kerberos keytabs:

- On your FreeIPA server (or on a client that has been enrolled and has the `ipa` set of commands), type:

```
ipa host-add <yourfreenas> # Enter your FreeNAS FQDN here
```

- Get the keytab file to install on your FreeNAS:

```
ipa-getkeytab -p host/yourfreenas -k freenas.keytab -e aes256-cts-hmac-sha1-96,aes128-cts-hmac-sha1-96 # you don't really need the -e and the encryption, but I used it as it worked better with some services
```

- Now, on your FreeNAS, go to `Directory Services`, `Kerberos keytabs` and click on `Add`
- Upload the file you just created

#### Configure the Kerberos Settings

I am not sure if this is necessary, but I configured it anyway:

- Go to `Directory services`, `Kerberos settings`
- Under `libdefaults Auxiliary parameters`, write this:

```
default_realm = YOURREALM # ex. MYREALM.LOCAL
dns_lookup_kdc = true
allow_weak_crypto = true
```

Good? Good. Now the real stuff:

#### Configuring LDAP

- Click on `Directory Services` and choose (guess what) `LDAP`
- On `hostname`, type the address of your FreeIPA server
- On `Base DN`, write what usually is your realm's DN: `dc=myrealm,dc=local`, for example
- Follow the documentation under "System Accounts" at [FreeIPA's LDAP how-to](https://www.freeipa.org/page/HowTo/LDAP) 
- If you followed the previous step, you might have ended up with a biding user like this: `uid=bidinguser,cn=sysaccounts,cn=etc,dc=myrealm,dc=local`. Copy that under `Bind DN` on your FreeNAS
- Enter the bind password as created following the steps above.
- Click `Advanced mode`
- On `Kerberos realm`, choose the realm you created
- On `Kerberos principal`, choose the host corresponding to the keytab you created
- Choose `START_TLS`
- Check on `Enable`
- Click on `Edit idmap`
- Adjust the Range low and Range high values. This is important because the default values won't reach the default range on FreeIPA. Be aware not to choose a range between 900000000 and 1000000000. The default values on FreeNAS are 20000 and 900000000, but these fall below the default values of FreeIPA. If you are using FreeIPA's default range, choose 1000000001 and 2000000000.
- You might want to repeat your User DN (same as the "Biding DN"), but it works for me without that. 
- You also might want to enter the URL, something like `https://myfreeipaserver.local`

That's it. Things might be working for you now!

A few notes:

- Your directory users do not show up on your main list of users under `Accounts`, but they will show up whenever you have the option to choose a user.
- Watch out for a little `i` icon on the top-right of your FreeNAS web interface - it shows the status of your connection to directory services.
- Type `id <someuserfromldap>` on the shell to see if you are retrieving users.

#### Things I didn't manage to get to work

I still haven't managed to make NFSv4 work with FreeNAS and this setup. I am basically finding the same problems described on this [forum post](https://www.truenas.com/community/threads/setting-up-nfsv4-and-kerberos.86335/#post-613819).

#### Conclusion

Using FreeIPA is great, and I wish I had tried it before. Having setup Nextcloud, FreeNAS, a mail server based on Postfix+Dovecot, Bitwarden, etc, it would have helped me extremly when it comes to centralize user information. 

Also, as I experiment a lot with some VM's, it would have helped me to mount my home directory on new servers, so that I could skip copying files. 

My next step is to create a replica of FreeIPA and start migrating the systems I use to it, so that user management might become easier.

Let me know if this guide helped you! 
