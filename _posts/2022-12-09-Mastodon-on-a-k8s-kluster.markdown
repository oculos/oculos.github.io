---
title:  Running a Mastodon instance on kubernetes
date:   2022-12-09 15:20:23 +0100
categories: personal
layout: post
comments: true
tags: mastodon kubernetes k8s
---

#### Introduction

I heard about [Mastodon](https://joinmastodon.org) when it got widely mentioned as a result of Elon Musk's Twitter acquisition. Its goal really got me interested, and I fell in love about it from day one.

I decided to run my own instance, [Mastodon.babb.be](https://mastodon.babb.be), and it has been a joy to use it and to maintain it.

I want users to come, but when I heard other stories of servers having to quickly scale up in order to accomodate the huge number of users coming from Twitter, I decided to get ready for such influx should it happen.

My goal was to setup a kubernetes cluster for my static websites, as well as for my old WordPress-based blog. The cluster was installed, everything seems to be running smooth (despite Ubuntu 22.04 quirks with kubernetes), so it was time to get Mastodon moved to it.

### The challenge

There were few recipes on how to move Mastodon to kubernetes.

Mastodon comes with a Helm chart, but I really didn't want to use it - some people out there say it is quite old. I also saw some other kubernetes deployments, but they were from more than four years ago, and a lot has changed.

## How

I had already a running, non containerized instance. So I had already a configured setup, which made things easier for me.

Initially, I used [Kompose](https://kompose.io) to convert the docker-compose.yaml supplied by Mastodon's [repo](https://github.com/mastodon/mastodon) to kubernetes deployments, services, etc.

After that, some cleaning up and adaptation, I did :

- throw out some files, like network configuration, redis, database and postgresql deployments, etc, as I run most of the persistent stuff outside my cluster.
- create several deployments for the sidekiq queues, as suggested by [Nora](https://nora.codes/post/scaling-mastodon-in-the-face-of-an-exodus/#fn:1).
- move sensitive key/values out of the env.production configMap to a secrets file
- created an ingress for web and another for streaming. I probably overdid it a bit, as I have a reverse proxy outside my cluster, so I moved some of nginx configuration from mastodon to my ingress, just to be on the safe side.
- finally, just for the kicks, I added a `topologySpreadConstraints` to my deployments to make sure the pods would be allocated evenly on my cluster (I got this one [here](https://medium.com/geekculture/kubernetes-distributing-pods-evenly-across-cluster-c6bdc9b49699).

I applied all the yaml and my cluster was then online.

## Remained things to do:

Remember the cronjobs? Well, we need those. I need to create a CronJob resource on my cluster, but, for now, what I did was that I stopped all my mastodon services on my original instance, but kept the cronjobs there. I'll remove those eventually and create CronJob instances on the cluster.

Please give me any comments or feedback. All the files I ended up using can be found on my [GitHub repo](https://github.com/oculos/mastodon-k8s).
