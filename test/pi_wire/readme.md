<br />
<p align="center">
  <a href="https://github.com/the-aerospace-corporation/satcat5">
    <img src="/doc/images/satcat5.png" alt="Logo" width="80" height="80">
  </a>

  <h3 align="center">PiWire</h3>

  <p align="center">
    A comphrehensive guide to installing/utilizing PiWire
    <br />
    <br />
    <a href="https://github.com/the-aerospace-corporation/satcat5">SatCat5 GitHub</a>
    ·
    <a href="https://github.com/the-aerospace-corporation/satcat5/blob/main/doc/CONTRIBUTING.md">Contributing to SatCat5</a>
    ·
    <a href="https://github.com/the-aerospace-corporation/satcat5/blob/main/doc/FAQ.md">General SatCat5 FAQ's</a>
  </p>
</p>



<!-- TABLE OF CONTENTS -->
<details open="open">
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#components-and-materials">Components and Materials</a></li>
        <li><a href="#raspberry-pi-configuration">Raspberry Pi Configuration</a></li>
        <li><a href="#arty-fpga-configuration">Arty FPGA Configuration</a></li>
      </ul>
    </li>
    <li><a href="#software-installation">Software Installation</a></li>
    <li>
      <a href="#supplemental">Supplemental</a>
      <ul>
        <li><a href="#oscilloscope-visualization">Oscilloscope Visualization</a></li>
        <li><a href="#loopback-testing">Loopback Testing</a></li>
        <li><a href="#debug-verbose">Debug Verbose</a></li>
      </ul>
    </li>
     <li><a href="#troubleshooting">Troubleshooting</a></li>
    <ul>
        <li><a href="#serial-device-configuration">Serial Device Configuration</a></li>
      </ul>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
## About The Project

Pi-Wire is a tool that turns a [Raspberry Pi](https://www.raspberrypi.org/) into a SatCat5 adapter. It allows a conventional Ethernet network to connect directly to a SatCat5 device, using either [SPI](https://en.wikipedia.org/wiki/Serial_Peripheral_Interface) or [UART](https://en.wikipedia.org/wiki/Universal_asynchronous_receiver-transmitter) protocols. This allows a low-cost adapter to connect a conventional Ethernet network to a SatCat5 switch or a SatCat5 device.

The name is intended to indicate that the device acts as close as possible to a wire. Ideally, it simply allows every packet through, verbatim, and doesn't act like an independent device. 

Initial development was by 2019 summer interns Henry Haase and Louis Stromeyer and continued by 2021 summer intern Giuliana Hofheins.  Current point of contact is Alex Utter.

The instructions below assume a Raspberry Pi 3+ running stock Raspbian (2021 May 7 build).


<!--### Components and Materials

 -->




<!-- GETTING STARTED -->
## Getting Started


### Components and Materials

* [Digilent Arty A7-35T](https://store.digilentinc.com/arty-a7-artix-7-fpga-development-board/)
* [Raspberry Pi 4 Kit](https://www.amazon.com/CanaKit-Raspberry-4GB-Starter-Kit/dp/B07V5JTMV9/)
  * A monitor, keyboard and mouse are also neccessary if utilizing the pi traditionally.
* [Samsung Evo MicroSD (32GB)](https://www.bestbuy.com/site/samsung-evo-plus-32gb-microsdhc-uhs-i-memory-card/5785401.p?skuId=5785401&ref=212&loc=1&extStoreId=1447&ref=212&loc=1&ds_rl=1268655&gclid=CjwKCAjwo4mIBhBsEiwAKgzXOH4a33zf5ORXoMnrxabIjKiRsC5jXUEB5pYjVhWyX-KfI2bF9p1ZPBoCLSsQAvD_BwE&gclsrc=aw.ds)
* [MicroSD Reader](https://www.amazon.com/Memory-Reader-Type-C-Adapter-Portable/dp/B07F6T9KHW/ref=asc_df_B07F6T9KHW/?tag=hyprod-20&linkCode=df0&hvadid=309818716690&hvpos=&hvnetw=g&hvrand=5037337349475534577&hvpone=&hvptwo=&hvqmt=&hvdev=c&hvdvcmdl=&hvlocint=&hvlocphy=9013518&hvtargid=pla-569151540883&psc=1)
* [TP-Link 5-Port Gigabit Ethernet Switch](https://www.amazon.com/Ethernet-Splitter-Optimization-Unmanaged-TL-SG105/dp/B00A128S24)
* [Adafruit Pi-RTC](https://www.digikey.com/en/products/detail/adafruit-industries-llc/3296/6238008)
* [Coin Cell Battery](https://www.adafruit.com/product/380)
* [Cat6 Ethernet Cables (x4)](https://www.amazon.com/AmazonBasics-RJ45-Cat-6-Ethernet-Patch-Cable-3-Feet-0-9-Meters/dp/B00N2VISLW)
* Male to Female Jumper Wires (x5)
* Optional
  * Oscilloscope+[Oscilloscope Probes](https://www.amazon.com/Hantek-300MHz-Oscilloscope-Switchable-Accessory/dp/B07P6DWRLZ/ref=zg_bs_5011669011_10?_encoding=UTF8&psc=1&refRID=YFHC945VS6ANAAQRTYRH)
  * [Ethernet to USB adapters](https://en.j5create.com/products/jue130)



### Raspberry Pi Configuration

1. If the heatsinks are not preinstalled on the SoC, memory, and GPU, they should be applied so the Raspberry Pi does not thermal throttle. The heat sinks are included in the Canakit package. Peel off the underside of the heat sinks and apply as shown below.

<p align="center">
  <img src="/doc/images/heatsinks.png" alt="heatsinks" width="325" height="200">
</p>
  
2. Install the coin cell into the RTC module, with the positive terminal of the battery aligned with the positive marking on top of the PiRTC.

<p align="center">
  <img src="/doc/images/RTC.png" alt="RTC" width="325" height="200">
 </p>

3. Download [Raspberry Pi Imager](https://www.raspberrypi.org/software/) and [Raspberry Pi OS](https://www.raspberrypi.org/software/operating-systems/). "Raspberry Pi OS with desktop and recommended software" is the reccomended OS. 

4. Plug in the USB SD card reader into PC, with the 32 CB microSD card inserted. Open the Raspberry Pi Imager, and etch the OS onto the microSD card. Eject after installation is finished. 

<p align="center">
  <img src="/doc/images/imager.png" alt="imager" width="325" height="200">
</p>

5. Place the 32 GB microSD into it's slot on the bottom of the Pi. Proceed by hooking up the monitor into the microHDMI0 port and the keyboard/mouse into USB 2/3 ports. Once the power source is plugged into the USB C, the Pi should immediately boot. 

### Arty FPGA Configuration

1. Connect the Raspberry Pi and the Arty FPGA by using male to female jumper wires, the Raspberry Pi pins and the PMOD ports found on the FPGA. 

<center>


|           | Default Pinout for Protocols |                               |
|-----------|------------------------------|-------------------------------|
| PMOD Pins |  UART Mode                   | SPI Mode                      |
| PMOD 1    | CTSb = RPi pin 6 (Ground)    | CSb = RPi pin 24 (SPI0-CS0)   |
| PMOD 2    | TxD = RPi pin 8 (UART0-Tx)   | MOSI = RPi pin 19 (SPI0-MOSI) |
| PMOD 3    | RxD = RPi pin 10 (UART0-Rx)  | MISO = RPi pin 21 (SPI0-MISO) |
| PMOD 4    | RTSb = No-connect / Unused   | SCK = RPi pin 23 (SPI0-SCLK)  |
| PMOD 5    | GND = RPi pin 14 (Ground)    | GND = RPi pin 25 (Ground)     |
| PMOD 6    | VCC = No-connect / Unused    | VCC = No-connect / Unused     |

</center>


<!-- USAGE EXAMPLES -->
## Software Installation

1. Download code as zip file from [SatCat5 Repository](https://github.com/the-aerospace-corporation/satcat5). Extract all files once downloaded. 

<p align="center">
  <img src="/doc/images/github.png" alt="github" width="325" height="200">
</p>

2. The easiest way to run Pi-Wire is to build it using the Raspberry Pi itself. Open the Raspberry Pi terminal. From the /test/pi_wire folder, compile and run using the following commands:

```console
pi@raspberrypi:~ $ cd /home/pi/Desktop/satcat5-main/test/pi_wire $ make all
pi@raspberrypi:~/Desktop/satcat5-main/test/pi_wire $ sudo ./pi_wire both

```
<p align="center">
  <img src="/doc/images/compileterminal.png" alt="compileterminal" width="400" height="200">
</p>

3. At this point, "both" can be replaced by "spi" or "uart" depending on protocol preference. ** Note, adjust path as needed depending on where the code is stored. Easiest way to confirm path is to copy it by right clicking on "test" folder in the Pi file finder. At this point, the program is running accordingly!



## Supplemental

### Oscilloscope Visualization

An oscilloscope is an electronic device that graphically displays signal voltages as a function of time. To visualize transmitted bytes and confirm the Raspberry Pi is sending data, the oscilloscope can be connected to correct GPIO pins for either SPI or UART protocols

1. Acquire an oscilloscope and probes. Connect the probes into channels one and two on the scope. 

|               | Oscilloscope/Pi Connections |                               |
|---------------|-----------------------------|-------------------------------|
| Scope Channel | UART mode                   | SPI Mode                      |
| Channel 1     | TxD = RPi pin 8 (UART0-Tx)  | SCK = RPi pin 23 (SPI0-SCLK)  |
| Channel 2     | RxD = RPi pin 10 (UART0-Rx) | MISO = RPi pin 21 (SPI0-MISO) |

1. To confirm data is being sent over UART Raspberry Pi pins with an oscilloscope, first connect hardware using information from the above table. 


2. From Raspberry Pi terminal, run the following command. The "50" is the baud rate, and can be adjusted to any of the typical rates (110, 300, 600,1200, 2400, 4800, 9600, 14400, 19200, 38400, 57600, 115200, 128000).

```console
pi@raspberrypi:~ $ stty /dev/ttyAMA0 50
```
  * Note: Some of the higher baud rates will be more difficult to visualize on the scope. It is recommended to use between 50-9600. 

3. Choose "autoset" on the oscilloscope. It will most likely be on a timescale too small to visualize packets, so adjust with the third channel knob.

4. To send a specific packet, run the following commands. The contents of the echo can be any string of characters. These bytes will be displayed on the scope as high/low voltages. 

```console
pi@raspberrypi:~ $ stty /dev/ttyAMA0 50
pi@raspberrypi:~ $ echo "asdfghjkl" > /dev/ttyAMA0
```

  * Note: At higher baud rates these packets resemble spikes. Decrease time scale to visualize more clearly

<p align="center">
  <img src="/doc/images/packetscope.jpeg" alt="packetscope" width="325" height="200">
</p>



### Loopback Testing
To test serial protocols, it is beneficial to utlize loopback testing. This tests the packets sent/received through shorting the transceiving/receiving pins.

##### SPI
This information is from [Raspberry Pi SPI Loopback Testing](https://importgeek.wordpress.com/2017/09/11/raspberry-pi-spi-loopback-testing/#comments)

1. Short the MOSI (RPi Pin 19,GPIO Pin 10) and MISO (RPi pin 21, GPIO Pin 09) pins. 

<p align="center">
  <img src="/doc/images/short.jpeg" alt="short" width="325" height="200">
</p>

3. Download code from [spidev-test](https://github.com/rm-hull/spidev-test). Confirm that spidev-test lists "spidev0.0" as the primary SPI device. 


 ```console
pi@raspberrypi:~ $ wget https://raw.githubusercontent.com/rm-hull/spidev-test/master/spidev_test.c
```

4. Compile the code using the command;

```console
pi@raspberrypi:~ $ gcc -o spidev_test spidev_test.c
```

4. Run the code. 

```console
pi@raspberrypi:~ $ ./spidev_test -D /dev/spidev0.0
```
<p align="center">
  <img src="/doc/images/spitest1.png" alt="spitest1" width="325" height="200">
</p>


5. If the hex characters are are '00', SPI is not functioning. Refer to Troubleshooting if this is the case. 

<p align="center">
  <img src="/doc/images/spitest2.png" alt="spitest1" width="325" height="200">
</p>

### Debug Verbose

To see the packets being sent/received as pi_wire is running, we can set the debugging verbosity level to different settings. In /test/pi_wire in slip.cpp, set the <code>#define DEBUG_VERBOSE 0</code> to either <code>#define DEBUG_VERBOSE 1</code> or <code>#define DEBUG_VERBOSE 2</code>. Compile and build, and be sure to run <code>make all</code> before running pi_wire. 


<p align="center">
  <img src="/doc/images/debugverbose.png" alt="debugverbose" width="375" height="200">
</p>

## Troubleshooting

### Serial Device Configuration 
 1. If any of the three initialized devices fail to initialize, verify the devices listed in lines 40-42 of main.cpp. 

```c
#define UART_DEV    "/dev/ttyAMA0"
#define ETH_DEV     "eth0"
#define SPI_DEV     "/dev/spidev0.0"
```

 2. Confirm that SPI is enabled using the following command;
```console
pi@raspberrypi:~ $ ls /dev/*spi*
```
If <code>/dev/spidev0.0  /dev/spidev0.1</code> is not outputted, then continue to "SPI configuration"  [SPI Configuration](#spi-configuration)

3. Run the following code. Confirm that <code> dtparam=spi=on</code> is uncommented. 
 ```console
pi@raspberrypi:~ $ sudo nano /boot/config.txt
```
4. To confirm correct UART settings, run the following. Confirm that <code> serial0 -> ttyAMA0</code>. If not, refer to [UART Configuration](#uart-configuration)
 ```console
pi@raspberrypi:~ $ ls -l /dev/serial*
```

#### SPI Configuration

Serial Peripheral Interfacing is not enabled by default. In order to utilize this program, please refer to the following steps. 

1. From **Start Menu > Preferences > Raspberry Pi Configuration > Interfaces** ensure that both **SPI** and **Serial Port** are enabled. After this, <code>reboot</code> to ensure that these changes take effect. 

   1b. An alternative is to reconfigure through terminal.
   1. Run <code>sudo raspi-config</code>
   2. Select <code>Interface Options</code> > <code>SPI</code>
   4. Enable SPI Interface
   5. If it prompts you to automatically load kernel, also select <code>yes</code>
   6. <code>Finish</code> and <code>reboot</code>


2. Refer back to Step 2 of [Serial Device Configuration](#serial-device-configuration) to confirm. 

#### UART Configuration

The two UART peripherals utilized by Raspberry Pi are ttyS0 and ttyAMA0. While ttyAMA0 offers the full set of features and is the default Serial0 on earlier models of RPi, it is now used for Bluetooth purposes on the later models while the less capable ttyS0 is set aside for the Linux serial console. To utilize Pi Wire, the full set of capabilities of the serial peripheral ttyAMA0 are needed. 

1. Run <code>sudo nano /boot/cmdline.txt</code> from terminal. Remove <code>console=serial0,115200</code>. 
2. Run <code>sudo nano /boot/config.txt</code>. Remove or comment out <code>enable_uart=0</code> and/or <code>enable_uart=1</code>. 
3. For RPi's with Bluetooth modules, ensure that <code>dtoverlay=pi3-disable-bt</code>, <code>dtoverlay=pi3-miniuart-bt</code>, <code>core_freq=250</code> are all added to <code>/boot/config.txt</code>. 
     1. Disable services that initializes bluetooth by running <code>sudo systemctl disable hciuart</code>. 
4. <code>reboot</code>

Test UART ports by referencing [Supplemental](#supplemental).

## Copyright Notice
Copyright 2019-2021 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.



