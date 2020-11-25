---
title:  Configuring a Linux image for Horizon instant clones, including Active Directory and NFSv4
date:   2020-11-24 17:20:23 +0100
categories: personal
layout: post
comments: true
tags: vmware horizon 
---

A pool of instant clones of VDI (Virtual Desktop Interface) is the one where an image of an OS is cloned so that several users can login to a similar computer set-up. Normally, these clones are destroyed and recreated, so it is common to setup an strategy for persistent storage.

VMWare has provided some documentation on how to configure Linux machines for those pools of instant clones, and arguably the most challenging part is the integration with Active Directory. Most of the documentation is linked on one document called [Integrating Linux with Active Directory](https://docs.vmware.com/en/VMware-Horizon-7/7.8/linux-desktops-setup/GUID-D8E3A4AA-83E9-46A4-8BBA-824027146E93.html#GUID-D8E3A4AA-83E9-46A4-8BBA-824027146E93). However, I've found that the documentation provided by VMWare can be a bit outdated or incomplete.

One example: On [this document](https://docs.vmware.com/en/VMware-Horizon-7/7.8/linux-desktops-setup/GUID-986977D4-87CE-459C-BC2A-55C0B6EA09AC.html), VMware doesn't mention that the clones need to rejoin the domain when created, though on a [document describe the procedure for RHEL](https://docs.vmware.com/en/VMware-Horizon-7/7.7/linux-desktops-setup/GUID-EA063015-63BB-44AE-BF66-D3ED2F1ABFF0.html) this is mentioned.

Another problem is that VMware skips the simplest of the situations, which is that AD can simply be joined by configurind SSSD correctly using ad as id_provider, auth_provider and access_provider, and not necessarily having to use [Winbind](https://docs.vmware.com/en/VMware-Horizon-7/7.8/linux-desktops-setup/GUID-524AE8EE-1084-4F1B-A6B0-553DABA06087.html), [Samba](https://docs.vmware.com/en/VMware-Horizon-7/7.8/linux-desktops-setup/GUID-986977D4-87CE-459C-BC2A-55C0B6EA09AC.html), [OpenLDAP](https://docs.vmware.com/en/VMware-Horizon-7/7.8/linux-desktops-setup/GUID-1E715FE3-0C00-45FC-B395-05D12E5D9E1A.html) or [LDAP authentication](https://docs.vmware.com/en/VMware-Horizon-7/7.8/linux-desktops-setup/GUID-1E715FE3-0C00-45FC-B395-05D12E5D9E1A.html) to achieve this.

This document attempts to supplement the information found elsewhere on how to properly configure a Linux OS image for deployment of an instant clones-pool. I used RHEL 8 here, but most of the things I mention can be used on other distros, though RHEL 8 is supported officially by Horizon 2006.

### Summary of the steps you need and what isn't covered here

I'm going to explain the following steps, which is what you need to configure your Linux image in order to get instant clones:

- Join the base (called golden image on VMWare documentation) to Active Directory
- Optinally configure `pam_mount` so that your users get home directories mounted from an NFSv4 server
- Make a decision on how you are going to save your credentials on the gold image so that the cloned images can (re)join the domain
- Write a script to orchestrate the rejoining
- Change the Horizon View agent configuration to run that script you created
- Shutdown the image, create a snapshot if it doesn't have one.

With these steps, you can deploy your image.

Things I don't mention here but I assume you have done them already:

- Create a user on AD for the purpose of joining other machines to AD
- Create the configuration for kerberos on `/etc/krb5.conf`
- Installation of the Horizon View Agent for Linux 
- DNS is working fine, the hosts resolve to the domain you're using, etc.

Ready? Let's do it!

### Setting up the image

#### Configuring your `/etc/sssd/sssd.conf`

As I said, VMware does not mention using AD as a source of authentication. Configure this by editing your `/etc/sssd/sssd.conf`. Here is an example of a working configuration:

```
[sssd]
config_file_version = 2
domains = mydomain.com
services = nss, pam, pac, sudo

[nss]
allowed_shells = *
default_shell = /bin/bash
shell_fallback = /bin/bash
homedir_substring = /home
override_homedir = %H/%u

filter_groups = root,apache,mysql,postgres,store,palantir,palconf,mailman
filter_users = root,apache,mysql,postgres,store,palantir,mailman,ghost,priss

[domain/EXAMPLE.COM]
id_provider = ad
auth_provider = ad
access_provider = ad
autofs_provider = ad
chpass_provider = ad
ldap_id_mapping = false # You might want to set this to true, but if you have uidNumber and gidNumber on your users' records, it works well with false.
enumerate = false
dns_discovery_domain = example.com

krb5_realm = EXAMPLE.COM
krb5_renewable_lifetime = 14d
krb5_renew_interval = 3600
krb5_ccname_template = FILE:%d/krb5cc_%U
ad_gpo_map_interactive = +gdm-vmwcred
```

Not all settings above are mandatory, but those are the ones that worked for us.


#### Join the domain

You can join the domain on a RHEL 8 install by using the `realm join`, but it configures a lot of the things which we already configured by hand on the sssd file. If you perform a `realm leave`, it ends up erasing your configuration, so I decided to use `adcli`.

But before joining the domain, it's important to decide if, when rejoining the domain on the clones, you are going to save the credentials or if you are going to use the password. Both have its advantages and disadvantages.

Using the password can be interesting if you don't plan to build your images too often. However, it is less secure, especially if the user you use to join AD has other capabilities. 

Using a password to join the domain is simple:

```
$ adcli join -U username@EXAMPLE.COM -D EXAMPLE.COM --service-name=nfs
```

*Note: the `--service-name=nfs` was used in case you are using an nfs service.*

Enter your password. Then if all goes well, you will have joined the domain. Test if you got the right tickets:

```
$ klist -ke
```

If, however, you prefer to cache your credentials on the image so that it can be reused by the clones for joining the domain, follow the instructions below. Using cache means that you need to rebuild the image so that clones can be created before these cached credentials get expired. 

```
$ kinit username@EXAMPLE.COM -f -A -r 30d -l 30d -c /root/mycachedcredentials
$ adcli join --login-ccache=/root/mycachedcredentials -D EXAMPLE.COM --service-name=nfs
```

There, no need of typing a password, as your credentials were read from the `mycachedcredentials` file. You can save it whenever you want.

If all goes well and you joined the domain, then let's make the final configurations.

#### Configuration for the Horizon View Agent

Ok, as I said before, the clones need to rejoin the domain, right? This is because they will have their own hostname, other ip addresses, etc., so it needs to join AD again. We need to orchestrate this. Luckly, VMWare helps us here with some settings. 

What you do want to do now is to create a script that will configure your clones with some settings and join the domain.

Here's a sample script that does the trick:

```
#! /bin/bash
# (Re)joins machine to AD after hostname is changed when instant clones are created.
# Must be called by /etc/vmware/viewagent-custom.conf

LOG=/tmp/ad-join.log # Because logging never killed anyone...
fqdn="$(hostname).example.com"
hostname="$(hostname)"
echo "This instant clone will joining ad..." >> $LOG
echo "Host: $(hostname)" >> $LOG

# Set new hostnames
hostname "$fqdn"
cat <<EOF > /etc/hosts
127.0.0.1 $hostname
::1   $hostname
EOF
echo "$fqdn" > /etc/host

# Stop SSSD so that the previous keytab is released from the cache
service sssd stop
sss_cache -E
rm -rf /var/lib/sss/mc/*
rm -rf /var/lib/sss/db/*
rm -rf /var/lib/sss/pubconf/*

# (Re)join AD
rm -rf /etc/krb5.keytab
adcli join --login-ccache=/root/mycachedcredentials -D EXAMPLE.COM --service-name=nfs
test $? -eq 0 || echo "Joining failed" >> $LOG
sleep 5
rm -rf /root/mycachedcredentials # Why leave your credentials on that clone? 

# Restart SSSD so we can authenticate again
service sssd start
```
Save this as, for example, `/usr/local/bin/ad-join.sh`.

If you want to use a password instead of the cached credentials, change tthe adcli line above to:

```
echo "myfancypassword" | adcli join --stdin-password -join -U username@EXAMPLE.COM -D EXAMPLE.COM --service-name=nfs
```

There is one detail that you might have seen here: we're stopping sssd and removing all its cache. This is important because the older keytab is still referred to by sssd. You get plenty of errors like this one if you don't stop sssd and refresh the cache prior rejoining the domain:

```
Failed to initialize credentials using keytab [MEMORY:/etc/krb5.keytab]: Preauthentication failed. Unable to create GSSAPI-encrypted LDAP connection.
```

This error was driving me crazy, and if you google it, most of the information will tell you that you need to remove the /etc/krb5.keytab, delete the account on AD, etc., but actually most of these things won't be necessary (Note that I do remove the old keytab). Stopping sssd and removing its cache prior rejoining the domain did the trick to fix this. Credits to [this forum post](https://access.redhat.com/discussions/2880321).

Now, one last step. Open `/etc/vmware/viewagent-custom.conf` and edit the following lines:

```
...
RunOnceScript=/usr/local/bin/ad-join.sh # or whatever the path/name you chose for your script
RunOnceScriptTimeout=120 # Adjust here if you believe that your rejoins take more than 2 minutes.
...
```

That's it! Now your image is fully configured for joining the domain. Shut it down, and create a snapshot with your modifications on vCenter, and schedule it to boot from your Horizon connection server.

But if you want to mount NFS shares as home directories, do the following step before shutting down your machine:

#### Setting up `pam_mount` for mounting home directories

There are a few ways to automount home directories, such as `autofs`. I used `pam_mount`, but might change it in the future for the flexibility of `autofs`.

Using NFSv4 with kerberos is a very good solution to mount those directories. If you got a kerberized NFSv4 server, why not?

With `pam_mount`, this was my configuration at `/etc/security/pam_mount.conf.xml`: 

```
 <volume
 fstype="nfs"
 server="serveraddress"
 uid="10000-100000" 
 path="/homedir/%(USER)"
 mountpoint="/home/%(USER)"
 options="vers=4,sec=krb5"
 noroot="0"
 />
```

Note the `id="10000-10000"` - remove it or adjust it accordingly. It basically means that we restrict mounting attempt to those uid's.

Now a last configuration: . On the file `/etc/idmapd.conf`, enter your domain:

```
Domain = example.com
```

Lastly, add the following line to the end of your `/etc/pam.d/password-auth` file in order to use `pam_mmount`: 

```
session     optional                                     pam_mount.so disable_pam_password disable_interactive
```

Things that might go wrong with `pam_mount`:

- SELinux is a $@#!$. Check your logs. If you use the `logout` configuration of `pam_mount`, it might require some adjustments of SELinux - you will see on your logs.
- Check your DNS. Do you get reverse domain lookups working, for example? 

### Final remarks

I hope this can help supplementing the information found on VMWare docs on how to integrate Linux to Active Directory with the purpose of offering pools of instant clones.

Any remarks, comments or tips? Feel free to comment! 


 
