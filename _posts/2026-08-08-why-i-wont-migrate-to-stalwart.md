---
title: Why I won't migrate from Postfix+Dovecot to Stalwart
date:   2026-08-08 09:05:23 +0100
categories: technology
layout: post
comments: true
tags:  postfix dovecot stalwart mail mailserver
---

### TL;DR and Disclaimer

Stalwart is excellent, but it replaces Dovecot's mail replication with cluster infrastructure I don't want to run for a personal setup - so I'm staying on Dovecot + Wormhole.

I feel Stalwart is the best option out there for those starting with a new mail server or who want to migrate to a cluster-based mail server. But for those who have been running Dovecot for a while, it won't be a very good replacement for their current setup.

I am by no means an expert on the art of being a postmaster. These reflections here are based on my own experience and limited knowledge and requirements.

This is not a comparison between Stalwart and Postfix+Dovecot - it is a description of why I wanted to migrate to Stalwart and why I realized it wasn't for me. For a thorough comparison between them, check this really [nice post](https://www.tobias-weiss.org/content/devops/dovecot-vs-stalwart-imap-production-comparison/). The only thing I disagree with Tobias Weiß, who wrote that post, about is when he counts mail sync as a feature of Stalwart. I don't think it has that feature, which is exactly why I didn't migrate.


### Me, myself and Postfix+Dovecot

Contrary to every advice, I decided in 2019 to host my own e-mail server. I'm glad I did it: not only did I learn a lot by doing so, but it feels good to be less dependent on a commercial and expensive mail provider. Today, according to a quick search on Google, about 60-90% of e-mail is provided by Microsoft, Google and the likes.

When the internet started, each ISP was an e-mail provider. That granularity is gone, and this is problematic for many reasons. I highlighted some of the problems [here](https://francisaugusto.com/2025/Email-quo-vadis-or-where-is-oidc-for-everyone/).

I admit: I didn't understand much of how the pieces of an e-mail ecosystem worked together. I followed an older version of [this article](https://www.scaleway.com/en/docs/tutorials/setup-postfix-ubuntu-bionic/) and set up my first e-mail server on some cheap ARM VPS on Scaleway. Good times...

As the years went by, I learned more about how things were tied together, and improved my setup.

### My current setup

Today, my setup has two important characteristics that are relevant for this article:

- Since around 2020, I started using Dovecot's now removed replication feature. This gave me peace of mind that whenever one server was down, the other would still receive e-mail and they would synchronize things back and forth. This saved me more than once throughout these years. It is therefore very important for me to have geographic redundancy when it comes to e-mail. I'd freak out if I lost an important e-mail.

- LDAP as the backend. Until around 2023, I used MariaDB+PostfixAdmin, which is a tool to manage e-mail addresses, aliases, domains, etc. It is a great tool, but when you have two servers, you'd have to replicate your database geographically, and that was a pain to maintain. Since I use [FreeIPA](https://www.freeipa.org), setting up replication was a breeze. But FreeIPA doesn't handle mail aliases, quotas, domains and virtual domains natively. So I developed the [FreeIPA PostfixAdmin plugin](https://github.com/oculos/freeipa-postfixadmin) which helped me mimic PostfixAdmin functionality on FreeIPA. It has worked beautifully so far.

The beauty (well, beauty is in the eye of the beholder) of this setup is that I had purely independent components that talked to each other. If one server was down, the other would answer. Each node has its own storage and user/password backend. I replicate the LDAP instances, but the rest doesn't need any replication because LDAP does it.

### Dovecot's apocalyptic removal of replication

Life was good, more family members started using my mail server. The combination with Roundcube for webmail, Solr for full-text search and Keycloak for single sign-on made this a perfect system. Of course, the lack of [modern authentication](https://francisaugusto.com/2025/Email-quo-vadis-or-where-is-oidc-for-everyone/) is still a problem for anyone selfhosting e-mail, but I now have a robust system which could resist downtime of one of the nodes and things would fix themselves.

But Dovecot removed its replication feature starting on version 2.4, leaving people like me in a very difficult situation: it is not good practice to run e-mail systems without a secondary MX server, as e-mail is critical. 

The removal of replication has prevented me from upgrading Dovecot, but now I have to do it. Or, I could migrate to Stalwart...

### Stalwart and why it is a great option

Stalwart is one of these things I wish existed when I started with e-mail. You configure most of the stuff on a GUI, it handles things such as DKIM, certificates, autoconfig/autodiscover and spam for you. And it is basically made for clusters. What is not to like?

I played a bit with it, and I am really impressed. 

I also like that the developer, while not as instantly responsive as Dovecot's mailing list people, always comes with a constructive answer. Fortunately, the Stalwart community is not plagued yet by that besserwisser (know-it-all) attitude one usually finds on mailing lists. You know the drill: you installed something cool, but you don't aspire to devote all your time to be an expert on it. Then you ask a question on a mailing list and chances are you'll get condescending answers and a tone that's not really helpful. My experience with Stalwart was stellar, even though the answers were not always exactly what I wanted to hear.

### So why won't I migrate to Stalwart?

Stalwart doesn't do mail replication - and that's the showstopper for me. It does make High Availability easy, but through a completely different mechanism, and that difference is the whole problem.

Here's the distinction. Dovecot's replication talks to a second server and synchronizes mailboxes between them, so each node holds its own complete copy of the mail. Stalwart instead treats storage and database as a single shared thing and asks you to make *that* redundant: you replicate your database (FoundationDB), your storage (Garage) and your cache (Redis or similar), and your mail becomes available from any node. Instead of replicating mail, you replicate the infrastructure underneath it - and that's powerful. 

This is probably great for companies or setups that already have a cluster setup, which allows Stalwart to scale so easily that it is beautiful to see.

However, here are the issues:

- If you don't have a cluster, you can still install several Stalwart nodes - but replicating the database and storage often (not always) requires three of them. I don't want three nodes. I just want my mail to still be there if one server goes down. 
- For personal/family use, I don't want to go through the hassle of setting up and maintaining a geographically redundant cluster. 
- Cluster-based database and storage doesn't give me the peace of mind Dovecot's replication does: if I lose all my mail on one node, it will be rebuilt as soon as it is set up. With Stalwart, if you lose your database or storage due to an accidental delete, the mail is gone forever. Stalwart sees the storage and the database as one, regardless of which node you use. You cannot even configure a Stalwart node individually to point to the geographically-closer db/storage. You can overcome this with some DNS rules and maybe with some pod/container affinity. 

So, basically, migrating to Stalwart and having redundancy requires you to provide a good deal of infrastructure which will increase the complexity of your setup, and will come with - for me - tough decisions when it comes to how to handle quorum decisions. 

Since I have two geographically distinct nodes, I had to set up a third node somewhere else just to accommodate FoundationDB and Garage's requirements. This is probably handled for you easily by an orchestrator like Kubernetes, but I'm not sure how I'd handle quorum decisions when one geographic region can't communicate with another. 

In other words, Stalwart has much fewer requirements to run compared to Dovecot, but it requires a much more complex infrastructure if you want to have a geographically redundant setup. 

### Was that all? 

No, unfortunately not. Those were the architectural reasons. Then came the practical ones.

I was willing to cope with that complexity. I installed a VPS on a third location just to cope with the quorum requirements of FoundationDB and Garage. I configured `/etc/hosts` so that each node would point to its closest Garage node. 

Things started to work, but then I came across other stuff:

- The documentation doesn't tell you, but if you want to have multiple nodes, you either need to provide some common cache (like Redis) or use what we - me and others - thought was the default mechanism for internode communication: Zenoh. You see, unless you want to go through the process of providing cluster-based cache, you need to use peer-to-peer node coordination.

I could use Redis or something like that, but then I'd need to configure their replication variations so that things would still work if one node goes down. I really don't want to do that, unless I must.

Unfortunately, you need to build your own Stalwart container to support Zenoh, which didn't work when I tried. I got a kind offer from the developer to fix it, but at this point I have given up the whole thing, also because I found other problems:

- Stalwart can be opinionated about how some things work. Take aliases. In Postfix, an alias can point to several mailboxes at once, and that single feature shaped how my family uses e-mail: we have one shared address - say, `family@ourdomain` - and a message sent there simply lands in each of our personal inboxes. No extra account to log into, no separate mailbox to check; it just shows up where we already read our mail. Stalwart limits you to one mailbox per alias and expects you to use a mailing list for this instead. But a mailing list is a different thing: it's a managed list with subscriptions and its own address semantics, not a transparent fan-out into the inboxes we already use. For a household, that's more moving parts to solve a problem Postfix solved with a single line. I really don't want that.

  My impression is that this comes down to how flexibly each system talks to LDAP. Postfix's LDAP configuration is remarkably powerful: it can accommodate an existing LDAP tree more or less as it already is, and it can even fire a second query to resolve and deduplicate the results of the first - so an alias that expands to several mailboxes just works, even against a directory that wasn't designed with mail aliases in mind. Stalwart, by contrast, seems to expect the tree to be laid out in a more rigid, predefined shape. When your directory (FreeIPA, in my case) came first and the mail server has to fit around it, that flexibility matters a lot. At least, that's my impression.
- Stalwart's authentication was a bit buggy for me on the web interface for some mailboxes because of their OAuth2 setup needing an attribute to check when a password was changed. Nothing I wouldn't be able to fix, and again the developer was quite helpful, but by this point I lost my faith in the whole thing.

You see, all I want for Chanukah is a mail system that works on two distinct regions. Dovecot does that. Well, at least it did that until they removed replication. But then I stumbled on [Wormhole](https://codeberg.org/errror/wormhole). I knew there were patches to Dovecot so one could bring replication back. But I didn't want to mess with Dovecot or its source code. However, Patrick Cernko created a plugin for Dovecot called Wormhole to bring the replication feature back. 

So my plan now is to upgrade to Dovecot 2.4.1 and get replication with Wormhole. That's all I need.

With Stalwart, I'd need to:

- install and maintain a third node for quorum requirements for database and storage, since one server doesn't replicate to another;
- cope with less functionality regarding aliases;
- deal with node orchestration or move my mail system entirely to a geographically redundant cluster

### Conclusion

Stalwart is a great product. I might migrate to it someday - or not, as I start to think about that day when I'll retire and will have to prepare an e-mail migration somewhere I'm not required to maintain things. This is distant in the future, but time runs fast...

However, for those who think about hosting e-mail themselves and who want some sort of redundancy, Stalwart, while itself being much less complicated than Dovecot to set up, comes with infrastructure requirements that are much more complex to meet - anyway, much more than I am willing to meet.

I do hope that Dovecot peeps will reconsider their decision to remove replication. Many people out there felt left alone in the rain when they did it.  

