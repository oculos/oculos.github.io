---
title:  Installing Matrix on Kubernetes - what they don't tell you
date:   2024-11-26 21:39:23 +0100
categories: personal
layout: post
comments: true
tags: kubernetes matrix synapse element
---

#### Disclaimer

I am no expert on Matrix or on Kubernetes. I just happen to use Kubernetes a bit, and got recently hooked on Matrix.

This is not a complete manual or guide on how to install Matrix on kubernetes. It is rather an introduction on the challenges you might experience and a heads up so you don't make the same mistakes I made.

#### Why are you writing this?

I wanted to install Matrix. I have install (and still maintain) a few opensource-based projects, specially Fediverse instances. I thought, what can't wrong, right? 

In my mind, these services follow the same design pattern, which is basically:

- a web-server/streaming service
- a few workers
- redis
- database

While Synapse (one of the implementations of the Matrix protocol) has these, its installation is challenge, mostly because:

- the documentation is not exactly the most idiot-proof,
- the workers do not behave like other works of, say, Mastodon,
- load balancing is tricky.

Of course, if you want to do something basic, [the official documentation](https://matrix.org/docs/older/understanding-synapse-hosting/) will get you going. But one someone installs something on a cluster, the main advantage is quick scalability. And that's the thing there are few guidelines about on the internet.

I'll comment a few things about the last two things on that list, but first, one little note: if you don't use Helm because, like me, you're too lazy to learn it, do yourself a favor and learn how to use it. I got away by not using it to all the stuff I deployed (mastodon, pixelfed, bookwyrm, etc). But Matrix is a beast. It's the kind of project you'd expect some help. I've seen people using [Nix](https://nix.dev/tutorials/nix-language.html) to maintain the deployment code, and if you speak Nix, lucky you. Someone I met on Matrix the other day send me [its setup](https://cgit.rory.gay/Rory-Open-Architecture.git/tree/host/Rory-nginx/services/matrix), which is a work of art.

But if you're lazy like me, you will have a lot of yaml writing to get this done.

So, get the configuration done by following the first steps of the abovementioned official documentation, and read along.

#### The workers

Workers are the main unit when you want to scale up things. On kubernetes, a worker usually is a deployment, so one just scale up the number of replicas.

It is a bit the same with Matrix, but with one caveat: 

Workers _need_ to have a unique name. Some of them, like the federation_sender's, need to be explicitly referred to on the main configuration. So you cannot simply go ahead and increate the number of workers. Or, you can, provided that they can be configured with a unique name. There might be many good strategies to do so in Helm or even without it. Mine was this:

```
 command: ["/bin/sh", "-c"]
          args:
           - |
             sed  "s/client_worker/${POD_NAME}/g" /config/client.yaml > /tmp/client.yaml &&
             exec python -m synapse.app.generic_worker \
             --config-path=/data/homeserver.yaml \
             --config-path=/tmp/client.yaml
          ports:
            - containerPort: 8022
              name: http
            - containerPort: 9093
          volumeMounts:
            - name: client-config
              mountPath: /config
              readOnly: true
            - name: matrix-volume-claim
              mountPath: /data
      volumes:
        - name: client-config
          configMap:
            name: client-config
        - name: matrix-volume-claim
          persistentVolumeClaim:
            claimName: matrix-volume-claim
      restartPolicy: Always
```
This is how I use the image to deploy a generic worker of the type client. The config map looks like this: 

```
onfigmap.yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: client-config
  namespace: matrix
data:
  client.yaml: |
    worker_name: client_worker
    worker_app: synapse.app.generic_worker
    worker_listeners:
      - type: http
        tls: false
        port: 8022
        resources:
          - names: [client,federation,media]
        bind_addresses: ["0.0.0.0"]
    redis:
      enabled: true
      host: 10.20.20.202
```

So when scaling up, it will modify the ConfigMap when creating the pod. This is great for deployments of workers that don't need to be on the `homeserver.yaml`. If you need those, I suggest using StatefulSets, since their names are predictable, and add them to the `homeserver.yaml`. Of course, unless you automate this, you need to adjust the amount of those workers on the main configuration manually if you increase or decrease them.

Check the [documentation](https://element-hq.github.io/synapse/latest/workers.html) on workers. Some must be only a single instance, others can scale up independently (as long as their name are unique), and some needs a restart of all workers and a configuration change to work.

#### Load balancing

On most services, load balancing is done by redirecting traffic to some sort of web workers. 

On Matrix, it is more complicate than that. Load balancing here is done mostly by isolating some endpoints closely related to each other, like synchronization or federation activities, and sending them to respective workers.

But besides that, two workers need more attention: federation inbound and sync.

Sync is done in such a way that load balancing is optimal if it's done by _user_. The documentation has a few tricks on how to do that. On an nginx server, this is kinda trivial. But on the nginx ingress controller, this can be a bit more complicate.

I went ahead and deployed a new ingress controller just for the matrix namespace on my cluster. That way, the rules I added won't be applied to traffic to other services.

I then added an http-snippet with the mappings mentioned on the documentation so I could get the variables to be used by nginx to do the load balancing: 

```
apiVersion: v1
data:
  allow-snippet-annotations: "true"
  annotations-risk-level: Critical
  http-snippet: |
     map $arg_since $sync {
     default "matrix-sync-8022";
     '' "matrix-sync-initial-8022";
     }
     map $arg_access_token $accesstoken_from_urlparam {
     default   $arg_access_token;
     "~syt_(?<username>.*?)_.*"           $username;
     }
     map $http_authorization $mxid_localpart {
     default                              $http_authorization;
     "~Bearer syt_(?<username>.*?)_.*"    $username;
     ""                                   $accesstoken_from_urlparam;
     }
  use-forwarded-headers: "true"
kind: ConfigMap
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/instance: matrix-ingress
    app.kubernetes.io/name: matrix-ingress
    app.kubernetes.io/part-of: matrix-ingress
    app.kubernetes.io/version: 1.12.0-beta.0
  name: ingress-nginx-controller
  namespace: matrix
```

You see that this requires predicting how nginx is going to refer to the services you create. Here, `matrix-sync-2022` is a deduction that the controller made by `<namespace>-<service name>-<portname>`.

That done, I used annotations on my ingress: 

```
    nginx.ingress.kubernetes.io/upstream-hash-by: "$mxid_localpart"
    nginx.ingress.kubernetes.io/configuration-snippet: |
        if ($request_uri !~ "^/_matrix/client/(unstable/org.matrix.simplified_msc3575|v5|v4|v3|r0|v1)/sync" ) {
        set $proxy_upstream_name $sync;
        }
```

This allows:
- sending initial synchronizations, which are heavier, to particular workers;
- load balancing things by the user

The federation inbound is nicer with load balancing by ip, so you update the `upstream-hash-by` with the `$remoteaddr` (I think and hope).

#### Conclusion


I really liked Matrix. It performs great if you don't go to a room with 50.000 people. It's installation, though, is very complex and granular. I heard that there are people that even create load balancing rules for a particular room, such as Matrix HQ, so that it won't steal much processing. 

I hope this was useful for you. And thanks to the guys on the "Matrix on kubernetes" room on the Matrix space who helped a lot to understand a few of those things.

