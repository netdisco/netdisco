



## Reworking of how portctl is made
Why ? We use Netdisco where I work to delegate administration permissions on 600+ switches of multiple constructors.
We regularly create/delete roles and change what that role can administrate in `deployment.yml`. 
But modifying that file triggers a restart of both web and backend, which is sorta blocking. 
Hence why I'd like the DB to store portctl roles and ACLs.
I hope this can be usefull to some more people.




**Netdisco** is a web-based network management tool suitable for small to very large networks. IP and MAC address data is collected into a PostgreSQL database using SNMP, CLI, or device APIs. Some of the things you can do with Netdisco:

* Locate a machine on the network by MAC or IP and show the switch port it lives at
* Turn off a switch port, or change the VLAN or PoE status of a port
* Inventory your network hardware by model, vendor, software and operating system
* Pretty pictures of your network

See the demo at: [https://netdisco2-demo.herokuapp.com/](https://netdisco2-demo.herokuapp.com/)

##  Installation

Netdisco is written in Perl and Python and is self-contained apart from the PostgreSQL database, so is very easy to install and runs well on any linux or unix system. We also have [docker images](https://store.docker.com/community/images/netdisco/netdisco) if you prefer.

It includes a lightweight web server for the interface, a backend daemon to gather data from your network, and a command line interface for troubleshooting. There is a simple configuration file in YAML format.

Please check out the [installation instructions](https://metacpan.org/pod/App::Netdisco) on CPAN. When upgrading, make sure to check the latest [Release Notes](https://github.com/netdisco/netdisco/wiki/Release-Notes).

You can also speak to someone in the [`#netdisco@libera`](https://kiwiirc.com/nextclient/irc.libera.chat/netdisco) IRC channel, or on the [community email list](https://lists.sourceforge.net/lists/listinfo/netdisco-users).

