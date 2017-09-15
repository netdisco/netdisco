# netdisco
[![Build Status](https://travis-ci.org/netdisco/netdisco.svg?branch=master)](https://travis-ci.org/netdisco/netdisco)
[![CPAN version](https://badge.fury.io/pl/App-Netdisco.svg)](https://metacpan.org/pod/App::Netdisco)

## Description
Netdisco is a web-based network management tool designed for network administrators. 

It's able to create a network topology and make some minor management on network devices.
The Data is collected from devices using SNMP and stored into a PostgreSQL database.

## Startup
Start the web-app server (accessible on port 5000)
```bash
~/bin/netdisco-web start
```
Start the daemon
```bash
# version 1.x
netdisco$~/bin/netdisco-backend start
# version 2.x
netdisco$ ~/bin/netdisco-daemon start
```

Main ressource:
 - [Main documentation on metacpan](https://metacpan.org/pod/App::Netdisco)
 
Other ressources:
- [Github wiki](https://github.com/netdisco/netdisco/wiki)
