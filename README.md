# netdisco
[![Build Status](https://travis-ci.org/netdisco/netdisco.svg?branch=master)](https://travis-ci.org/netdisco/netdisco)
[![CPAN version](https://badge.fury.io/pl/App-Netdisco.svg)](https://metacpan.org/pod/App::Netdisco)

## Description
Netdisco is a web-based network management tool designed for network
administrators. Data is collected into a PostgreSQL database using SNMP.

Some of the things you can do with Netdisco:

* Locate a machine on the network by MAC or IP and show the switch port it lives at
* Turn off a switch port, or change the VLAN or PoE status of a port
* Inventory your network hardware by model, vendor, software and operating system
* Pretty pictures of your network

App::Netdisco provides a web frontend with built-in web server, and a backend
daemon to gather information from your network, and handle interactive
requests such as changing port or device properties.

## Startup
Start the web-app server (accessible on port 5000)
```bash
~/bin/netdisco-web start
```
Start the daemon
```bash
netdisco$ ~/bin/netdisco-backend start
```

Main resource:
 - [Main documentation on metacpan](https://metacpan.org/pod/App::Netdisco)
 
Other resources:
- [Github wiki](https://github.com/netdisco/netdisco/wiki)
