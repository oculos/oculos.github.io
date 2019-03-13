---
title:  "WiFi ESXi on the 2018 Mac Mini - networking"
date:   2019-03-12 19:34:23 +0100
categories: personal
layout: post
comments: true
tags: esxi mac-mini aquantia
---

My [workplace](https://www.uio.no) aquired a few of the 2018 Mac Mini's so that we could upgrade our support for macOS users. Our plan was to use this machine as a cluster, ideally running ESXi on them. It was great when we read [here](https://www.virtuallyghetto.com/2018/11/esxi-on-the-new-2018-apple-mac-mini.html) that it appeared that ESXi 6.7 runs fine on those machines.

Nevertheless it was disappointing to see that a lot of things don't work:

- The internal storage cannot be used
- Thunderbolt controllers are not supported

For us it was even worse: the model we bought has 10Gb NICs, which lacks ESXi drivers. This means that we could not even install ESXi on the Mac Mini, as the installer seems to require a driver.

Well, now we managed it.

Following some good tutorials [here](https://www.v-front.de/2014/12/how-to-make-your-unsupported-nic-work.html) and [here](http://www.vm-help.com/forum/viewtopic.php?f=34&t=4340), I started an attempt to port the [freely available Linux drivers](https://www.aquantia.com/support/driver-download/) from [Aquantia](https://www.aquantia.com). This was not an easy task, as VMware does not document all that well how to setup the environment for building up things. After a while, with a proper configured CentOS environment, I started the process.

But then I've hitten a wall, and couldn't go further. On a desperate attempt, I contacted Aquantia to see if they were interesting into porting their Linux drivers to ESXi. Well, it turns out they were, and today I finally got a candidate version that worked amazingly well on our Mac Mini's. 

![ESXi on 10Gb Mac Mini]({{"/assets/2019/mac-mini-esxi.png" | absolute_url}} )

I haven't tested it exhaustively so far, let alone on a 10Gb switch, but so far, so good. 

![aquantia]({{"/assets/2019/aquantia-mac-mini.png" | absolute_url}} )
 
The Aquantia folks did all the job, so I'm really grateful. From what I understand they are going to release the driver in the near future when things are ready on their side.

It's great to know that the Mac Mini can be a viable option to run ESXi. Of course, because the Mac Mini is not a supported platform for ESXi, it is uncertain how things are going to be after VMWare drops support for Vmklinux-based drivers. 

On top of that, somethings to notice:

- I couldn't get any storage - USB or USB-C - to work. Booting with storage plugged on a legacy USB port would do nothing at best and prevent booting at worse (I got an error once saying something aobut multiboot not being supported). Hot-plugging to USB/USB-C doesn't get the device to show up, and booting with anything, I mean, ANYTHING, connected to a USB-C port would lead me to the purple screen of death (PSOD). So it's gonna be either SAN or installing the ESXi on one of [these](https://www.samsung.com/semiconductor/minisite/ssd/product/portable/t5/) so that we can have some room for our VM's. But maybe it needs to be [manually mounted](https://www.virten.net/2016/11/usb-devices-as-vmfs-datastore-in-vsphere-esxi-6-5/)?
- The Aquantia driver worked fine on the internal NIC, but I couldn't make the Apple USB Ethernet adapters to work - ~~these adapters apparently also use chipset from Aquantia~~ this adapters use ASIX chipset ax88772A, not supported by the usb nic driver mentioned below, but I am not surprised, since USB doesn't seem to work well on ESXi on the Mini. Booting with a Realtek-based USB-C Ethernet adapter would bring me a PSOD, and I don't have a Realtek based USB adapter, so I couldn't test the [USB NIC driver](https://labs.vmware.com/flings/usb-network-native-driver-for-esxi). I did inject it on my ISO, though.

Long story short, things look promising. Due to Apple licensing terms, we can only run a virtualized instance of macOS on Apple hardware. Using macOS VM's could help us on our job, and the nice work of Aquantia is going to make that possible.

Leave a message in the comments if you too are contemplating running ESXi on a 10Gb Mac Mini!

(UPDATED on 13.3.2019 to correct info on Apple's USB Ethernet adapter.)