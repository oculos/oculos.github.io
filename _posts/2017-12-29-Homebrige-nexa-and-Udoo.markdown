---
title:  "Homebridge, Nexa switches and Udoo Neo"
date:   2017-12-29 20:13:23 +0100
categories: personal
layout: post
comments: true
tags: projects homebridge
---

The year is ending and I would like to finish it with a cool project.

I am a sucker for gadgets, especially small cheap computers like the [Raspberry Pi](https://www.raspberrypi.org). Some years ago, I contributed to a [Kickstarter](https://Kickstarter.com) project called [Udoo Neo](https://www.udoo.org/get-started-neo/), which is a credit-sized computer + Arduino. It also came with some sensors for measuring the temperature and barometric pressure. I used it as a tool to monitor the temperature on our living room and to run some experiments.

I have lots of [Arduino boards](https://arduino.cc) that I used on other projects, such as an automatic system to water my plants. I wanted to experiment with 433mhz transmitters, mostly because they are cheap and I wanted to use them to study basic network concepts.

On my flat we have some lights on our living room that are plugged to outlets and controlled via remote control. I use a cheap [Nexa](https://nexa.se) PE-3 kit. [This](https://www.clasohlson.com/no/Nexa-PE-3-3-pack-fjernstrømbrytere/36-4602) is the exact model.

I realized that those Nexa outlets use the 433mhz frequency, so I kept thinking about controlling the lights plugged into them with an Arduino at some point, but didn't have a reason for that (other than the gimmick aspect of it). That changed when I came across [this post](https://medium.com/arvin-singla/apple-homekit-hacking-3d2902e7a1df), where the author describes how he used [Homebridge](https://github.com/nfarina/homebridge) to control his remote lights. But what is Homebridge?

Well, if you are an Apple-fanboy like me, you know that Apple has a technology called HomeKit that allows you to control devices on your home from your iPhone, iPad or Apple TV. But there are not so many devices available for HomeKit yet, and those that are available  are expensive. Enter Homebridge, an open source project that allows you to create your own accessories for HomeKit. You see where I am going: if I can control my outlets with Arduino, maybe I could connect that with Homebridge and ta-daaa, I would be able to switch my lights on and off (as well as I could see my room's temperature on my phone using a temperature sensor connected to the Udoo).

As I said, I had an Udoo laying around, and lots of cheap 433 receivers and transmitters. So my goal was:

*   to control my light switches with my Udoo Neo;
*   to install Homebridge on the Udoo Neo;
*   to be able to control my lights switches via my iPhone.

### Controlling my light switches with Udoo Neo

There are many cool projects for the Arduino that allow you to record the commands you send from a 433mhz remote control and to send those command backs. Before trying with my Udoo Neo, I tried first with my Arduino, and these sketches/products worked fine:

*   [Sketches to learn and send back commands](http://fritzing.org/media/fritzing-repo/projects/n/nexardu-illumination-smart-control/code/), which is a modification of [this](http://playground.arduino.cc/Code/HomeEasy). I used [this sketch](http://fritzing.org/media/fritzing-repo/projects/n/nexardu-illumination-smart-control/code/Nexa_Ok_3_RX.ino) to learn the codes of my remote control, and then I used [NexaCtrl](https://github.com/calle-gunnarsson/NexaCtrl) to actually send the commands.
*   [rc-switch-fork](https://433mhz.codeplex.com/SourceControl/latest#rc-switch-fork/RCTransmitter.cpp) worked great as well. The original [rc-switch](https://github.com/sui77/rc-switch/wiki) didn't work.  

The problem is that *none of those worked on my Udoo Neo*. You see, the Arduino on the Udoo Neo is not based on the AVR architecture of the "common" arduinos. Therefore, the solutions above didn't work with my Udoo Neo. I suspect the libraries used by those packages rely on stuff available only to Arduinos based on AVR. I could simply connect an Arduino to the Udoo Neo and get this done, but I thought it would be a waste of resources.

I then decided to give [this great tutorial](http://arduinobasics.blogspot.no/2014/06/433-mhz-rf-module-with-arduino-tutorial.html) a try. I have bookmarked it a while ago because it is not a tutorial for a ready-made solution - well, it offers that as well - but remember when I said I wanted to study some basic network concepts? This tutorial teaches how to recognize basic signals typically used for this kind of communication between devices and I always thought I could try to replicate what he did one day. Well, this day has come.

What I did was that I used the [code he made to learn commands from a remote control](http://arduinobasics.blogspot.no/2014/07/433-mhz-rf-module-with-arduino-tutorial_30.html), then I printed the array of each command for my remote control on Arduino's serial monitor, and created another sketch where I hard coded the commands by pasting the array so that I could send these codes. Not super elegant, but it works.

Since using the Arduino interface on the Udoo Neo is irritating (I access it via VNC), I decided to read the commands on an Arduino connected to my Mac, and transfer a sketch with the codes to the Udoo Neo. That sketch would read the serial interface, and when it receives a certain instruction from the Linux side of the Udoo Neo, it would then send the right code to turn a specific light on or off. The same scenario as if one were using a Raspberry Pi connected to an Arduino. It is also possible to send those signals using a Raspberry Pi, without an Arduino. I might try that at some point.

It worked! It wasn't as reliable as on the Arduino connected to my Mac - I have to power off the transmitter every time I am not using it, but it worked.

Then I created a python script to send the commands via serial to the built-in Arduino of the Udoo Neo. Something like this:

```
> python lightcontrol.py 1 off # turn the light 1 off
Light 1 is off
```

After that was done, it was time to install Homebridge.

### Installing Homebridge on the Udoo Neo

I did it following [this tutorial here](https://github.com/nfarina/homebridge/wiki/Running-HomeBridge-on-a-Raspberry-Pi). One note: make sure you are installing the absolutely latest version of NodeJS.

I wasn't familiar with `npm`, so I found strange that on the docs of the project or on [this excellent guide on how to write a Homebridge plugin](http://blog.theodo.fr/2017/08/make-siri-perfect-home-companion-devices-not-supported-apple-homekit/) it was always suggested to publish plugins to a plugin repository. I didn't do it. I simply created a local plugin by creating a directory on `/usr/lib/node_modules`, and then I created the proper `index.js` and `package.json`. I don't see a reason to make my plugin public, as I imagine that my solution is very tied to the system I am using. Of course, if anyone feels he might benefit from it, just drop me a note. Remember:

* Your plugin must start with `homebridge`, for example, `homebridge-myplugin`
* Do not follow the code he shows on the tutorial, but rather [the code he actually wrote for his project](https://github.com/fredericbarthelet/homebridge-smappee/blob/master/index.js). I found it more up to date.

The result is that now I can control all the lights on my room with my iPhone/Apple watch, even with Siri, with very cheap equipment I already had!

This is how it looks:

![This is how it looks]({{"/assets/homebridge.png" | absolute_url}} )

My `index.js` file looks like this:

{% highlight javascript %}
var fs = require('fs');
var Service, Characteristic;

module.exports = function (homebridge) {
    Service = homebridge.hap.Service;
    Characteristic = homebridge.hap.Characteristic;
          homebridge.registerAccessory("homebridge-lightcontroller", "LightController", myLightController);
    homebridge.registerAccessory("homebridge-lightcontroller","Temperature",myTemperature);
};

function myTemperature(log,config){
    this.log = log;
    this.serviceAccessory = new Service.AccessoryInformation();
    this.serviceAccessory
        .setCharacteristic(Characteristic.Manufacturer, "Francis");
    this.serviceTemp = new Service.TemperatureSensor("Living room temperature");
    this.serviceTemp
        .getCharacteristic(Characteristic.CurrentTemperature)
        .on('get',this.getTemp.bind(this));
}

myTemperature.prototype.getServices = function() {
    return [this.serviceAccessory, this.serviceTemp];
}

myTemperature.prototype.getTemp = function(callback){
    fs.readFile('/sys/class/i2c-dev/i2c-1/device/1-0048/temp1_input', 'utf8', function(err, data) {
            if (err) {
                    callback(err);
                    return
                }
    callback(null, parseFloat(data)/1000)
  })
}

function myLightController(log, config) {
    this.log = log;
    this.command = config['command'];
    this.acc = config['acc'];
    this.serviceAccessory = new Service.AccessoryInformation();
    this.serviceAccessory
        .setCharacteristic(Characteristic.Manufacturer, "Francis");
    this.serviceSwitch = new Service.Switch("My Light Controller");
    this.serviceSwitch
        .getCharacteristic(Characteristic.On)
        .on('set', this.setPowerState.bind(this));
}

myLightController.prototype.getServices = function(){
  return [this.serviceAccessory,this.serviceSwitch];
}

myLightController.prototype.setPowerState =  function (on, next) {
    onOff = "";
    if (on){
        onOff = "on";
        } else {
        onOff = "off";
    }
    comm = this.command+" "+this.acc+" "+onOff;
    this.serviceAccessory = new Service.AccessoryInformation();
    this.serviceAccessory
        .setCharacteristic(Characteristic.Manufacturer, "Francis");
    this.serviceSwitch = new Service.Switch("My Light Controller");
    this.serviceSwitch
        .getCharacteristic(Characteristic.On)
        .on('set', this.setPowerState.bind(this));
}

myLightController.prototype.getServices = function(){
       return [this.serviceAccessory,this.serviceSwitch];
}

myLightController.prototype.setPowerState =  function (on, next) {
   onOff = "";
   if (on){
       onOff = "on";
   }else {
       onOff = "off";
   }
   comm = this.command+" "+this.acc+" "+onOff;
   const { exec } = require('child_process');
   exec(comm, (err, stdout, stderr) => {
       if (err) {
                 // node couldn't execute the command
                 return next(err);
   });
   return next();
 }
{% endhighlight %}

The only caveat with this system is that if I turn the light off using the remote control, the state of the lamp on the Home app will not reflect the actual state. This is the only limitation, and it can be a problem if you are considering some form for automation, as the system might skip turning something on as the state is already on.
