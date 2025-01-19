---
title:  The complexities of running a Fediverse instance on clusters
date:   2025-19-01 17:01:23 +0100
categories: personal
layout: post
comments: true
tags: kubernetes fediverse mastodon pixelfed bookwyrm friendica
---

#### Disclaimer

I am no expert on Kubernetes and neither have I a deeper understand of all the components of the different Fediverse servers. What I am writing here is a result of my own impressions, which may be incorrect or misleading.

#### Introduction

I started to run Fediverse instances in november 2022. Our Mastodon instance, [Babb.no](https://babb.no) has been running since. Since then, I also started to run a [Pixelfed instance](https://pixelfed.babb.no), a [Bookwyrm instance](https://books.babb.no) and finally a [Friendica instance](https://social.babb.no).

My goal was to offer colleagues and friends a gateway to healthier social networks. Well, those didn't come, so I opened these networks to everyone.

Since I don't have exaactly so much free time to understand these services and fix or scale them when the need that, it is important for me that I can run those services on a kubernetes cluster, to have a nice forum to exchange information on how to fix things, and to have good documentation.

Sadly, these services are not always easy to understand. They have sometimes a lot of components and it is not trivial to understand what they do nor how they relate to each other.

I want to compare how these instances in three areas:

- cluster deployability
- documentation
- support community for sysadmins

#### Cluster deployability

These days, enterprise environments for web services are hosted on cluster like Kubernetes. 

However, because Fediverse instances are primarily run by individuals with limited access to resources, I suspect that there are few tutorials, if at all, on how to run Fediverse instances on a cluster.

Among all the servers, things vary considerably. From having a helm chart, to not even mentioning clusters at all. 

The main problem here is that there is very little documentation on which  components can or need to be deployed separately so that one can use cluster for redundancy and high availability. 

Mastodon is clearly the winner here. It provides Helm charts, so one can have things deployed quite easily. However, I didn't go that route. I used their Docker compose file, read a lot of posts about mastodon sidekiq workers, and created my yaml files using [Kompose](https://kompose.io). It gave lots of flexibility back in the days, though today I'd probably force myself to understand Helm.

Pixelfed didn't have an official Docker image back in the days, so I got a Dockerfile somewhere, and deployed it myself. Luckly, its design is simple - one needs a web container and a worker container. Both can scale, and it works fine.

Bookwyrm wasn't so easy either, to the point I created my [own repo](https://github.com/oculos/bookwyrm-kubernetes) with configuration files.

The problem with Bookwyrm, and as well as with Friendica, is that while they do provide ready-made docker images, they are based on the premise of a single node deployment. So we end up having a redundant Nginx container, and on neither of those we have a clear idea on a good deployment architecture.

A little digression here: people deploy clusters differently when it comes to web access: some have an ingress (Nginx) exposed to the world, some have a reverse proxy pointing to services, some (like me) have a reverse proxy that proxy requests to an ingress. 

So a clear documentation on what is the best way to implement routes, block paths, etc, would be great for cluster maintainers.

Bookwyrm is probably scalable - I never tried to increase the number of its workers, but I see no reason why it wouldn't work.

Friendica was the hardest due its confusing docker documentation, no good php-fpm tweaks (like for example fixing `pm.max_children` needs to be done manually) and no scalability whatsoever. I guess that at some point I'll have to limit the number of new users. One may most likely increase the Nginx pods, but there is no worker scalability.

#### Documentation

While none of those servers have cluster-specific documentation, they have some documentation of configuration items.

Mastodon is again the winner. With a mature structure and development, it has an up-to-date documentation on all configuration options, though some are not explained on the list of configuration parameters. For example, `PAPERCLIP_ROOT_URI` is listed as valid configuration, but you'd have no idea of what it is used for unless you read its Object storage configuration (even though this applies to local, filesystem storage).

Bookwyrm has a good installation, but not good index of configuration options, which is useful when converting installation patterns to a cluster.

Pixelfed was very good before, but the documentation is so outdated these days that some configuration is only found on the source code. Fortunately, the main developer is accessible and usually helps right away.

Friendica has documentation on different sites, which is confusing, as you don't know what's current and what's old. It's a wiki and documentation site. This makes find things difficult

#### Community and help for sysadmins

If you're a Patreon to Mastodon, you get access to their Discord. There, there's a channel for sysadmins (I miss the term "sysops"), and one gets a lot of help. It has saved me many times, so I feel a bit safer knowing I'm not on my own.

Pixelfed also has a Discord and a channel there for sysadmins. However, help, true help, comes only from it's main (only?) writer. So one's milleage may vary: if you need help when it's night in Canada, you'll have to wait. Unfortunately, Pixelfed is highly dependant on one developer, and it's impressive that, in spite of this dependancy, things go well and one does get help. It just might take a bit of time.

Bookwyrm has a Matrix room for admins, but seldom one gets help there. Sometimes posting on their github issues will get attention, but it might take weeks. I feel that development there is quite stalled, but I hope I'm wrong.

Friendica was very difficult for me one year ago when I tried for the first time. Nobody was running it on Kubernetes. Replies were vague, and it was hard to get help. I gave it a try again recently, and, while I haven't anyone running it on a cluster, I did get better help this time on their group on, well, on Friendica. They do have a Matrix room, but I didn't get too much help there.

#### Conclusion

I want to make clear all this is based on my own experience, and it might be based on misunderstanding on where to get help or configuration information.

That said, if you're planning on deploying and maintaining a Fediverse instance on a cluster or any other deployment that's different than the instance's default install instructions, you might be on your own.

Mastodon, being much more mature than the others, have a robust community of developers and seasoned admins who almost certainly will help you.

Unfortunately, that can't be said about the other fediverse services. I do hope that these services gain critical mass so that they'll get more resources and make them easier to administer.
