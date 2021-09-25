use strict;
use warnings;
use DBIx::DataModel;

DBIx::DataModel  # no semicolon (intentional)

#---------------------------------------------------------------------#
#                         SCHEMA DECLARATION                          #
#---------------------------------------------------------------------#
->Schema('App::Netdisco::AutoCRUD::Schema')

#---------------------------------------------------------------------#
#                         TABLE DECLARATIONS                          #
#---------------------------------------------------------------------#
#          Class                Table                  PK                  
#          =====                =====                  ==                  
->Table(qw/UserLog              user_log                                   /)
->Table(qw/Process              process                                    /)
->Table(qw/Session              sessions               id                  /)
->Table(qw/DeviceModule         device_module          ip index            /)
->Table(qw/NetmapPositions      netmap_positions       id                  /)
->Table(qw/Community            community              ip                  /)
->Table(qw/Node                 node                   mac switch port vlan/)
->Table(qw/DevicePortWireless   device_port_wireless   port ip             /)
->Table(qw/DeviceIp             device_ip              ip alias            /)
->Table(qw/DevicePower          device_power           ip module           /)
->Table(qw/DevicePortLog        device_port_log        id                  /)
->Table(qw/DevicePort           device_port            port ip             /)
->Table(qw/Topology             topology                                   /)
->Table(qw/DeviceVlan           device_vlan            ip vlan             /)
->Table(qw/NodeIp               node_ip                mac ip              /)
->Table(qw/NodeMonitor          node_monitor           mac                 /)
->Table(qw/Statistics           statistics             day                 /)
->Table(qw/NodeNbt              node_nbt               mac                 /)
->Table(qw/DevicePortProperties device_port_properties port ip             /)
->Table(qw/Device               device                 ip                  /)
->Table(qw/DevicePortPower      device_port_power      port ip             /)
->Table(qw/DeviceSkip           device_skip            backend device      /)
->Table(qw/User                 users                  username            /)
->Table(qw/Admin                admin                  job                 /)
->Table(qw/NodeWireless         node_wireless          mac ssid            /)
->Table(qw/Subnet               subnets                net                 /)
->Table(qw/DevicePortSsid       device_port_ssid       ip bssid port       /)
->Table(qw/Log                  log                                        /)
->Table(qw/Oui                  oui                    oui                 /)
->Table(qw/DevicePortVlan       device_port_vlan       ip port vlan native /)

#---------------------------------------------------------------------#
#                      ASSOCIATION DECLARATIONS                       #
#---------------------------------------------------------------------#
#     Class                Role                   Mult Join    
#     =====                ====                   ==== ====    
->Association(
  [qw/DeviceVlan           vlan                   1    ip      /],
  [qw/DevicePortVlan       ---                    1    ip      /])

->Association(
  [qw/Node                 ---                    1    mac     /],
  [qw/Virtual::NodeIp4     ip4s                   *    mac     /])

->Association(
  [qw/DevicePort           ---                    1    port    /],
  [qw/DevicePortLog        logs                   *    port    /])

->Association(
  [qw/DevicePortProperties ---                    1    port    /],
  [qw/DevicePort           port                   1    port    /])

->Association(
  [qw/DevicePort           ---                    1    port    /],
  [qw/DevicePortVlan       port_vlans             *    port    /])

->Association(
  [qw/DevicePower          device_module          1    ip      /],
  [qw/DevicePortPower      ---                    1    ip      /])

->Association(
  [qw/NodeIp               ---                    1    mac     /],
  [qw/Node                 nodes                  *    mac     /])

->Association(
  [qw/Virtual::LastNode    last_node              0..1 port    /],
  [qw/DevicePort           ---                    1    port    /])

->Association(
  [qw/Topology             ---                    1    dev2    /],
  [qw/Device               device2                1    ip      /])

->Association(
  [qw/Device               target                 0..1 ip      /],
  [qw/Admin                _2                     1    device  /])

->Association(
  [qw/Node                 node                   0..1 mac     /],
  [qw/NodeWireless         wireless               *    mac     /])

->Association(
  [qw/DevicePort           ---                    1    port    /],
  [qw/Virtual::NodeWithAge nodes_with_age         *    port    /])

->Association(
  [qw/DeviceVlan           _2                     1    vlan    /],
  [qw/DevicePortVlan       ports                  *    vlan    /])

->Association(
  [qw/NodeNbt              netbios                0..1 mac     /],
  [qw/Node                 nodes                  *    mac     /])

->Association(
  [qw/Virtual::DevicePortSpeed throughput             1    ip      /],
  [qw/Device               ---                    1    ip      /])

->Association(
  [qw/DevicePortPower      power                  0..1 ip      /],
  [qw/DevicePort           port                   1    ip      /])

->Association(
  [qw/Device               device                 1    ip      /],
  [qw/DevicePortVlan       port_vlans             1..* ip      /])

->Association(
  [qw/Node                 ---                    1    mac     /],
  [qw/Virtual::NodeIp6     ip6s                   *    mac     /])

->Association(
  [qw/Device               device                 1    ip      /],
  [qw/DevicePort           ports                  *    ip      /])

->Association(
  [qw/DevicePortSsid       _2                     1    port    /],
  [qw/Node                 nodes                  *    port    /])

->Association(
  [qw/NodeIp               ---                    1    mac     /],
  [qw/NodeNbt              netbios                *    mac     /])

->Association(
  [qw/DevicePortProperties properties             0..1 ip      /],
  [qw/DevicePort           ---                    1    ip      /])

->Association(
  [qw/Device               device                 1    ip      /],
  [qw/DeviceVlan           vlans                  *    ip      /])

->Association(
  [qw/Node                 _3                     1    switch  /],
  [qw/Device               device                 0..1 ip      /])

->Association(
  [qw/DevicePower          ---                    1    module  /],
  [qw/DevicePortPower      ports                  *    module  /])

->Association(
  [qw/Topology             _4                     1    dev1    /],
  [qw/Device               device1                1    ip      /])

->Association(
  [qw/DevicePort           _3                     1    port    /],
  [qw/Node                 nodes                  *    port    /])

->Association(
  [qw/DevicePortWireless   _4                     1    port    /],
  [qw/Node                 nodes                  *    port    /])

->Association(
  [qw/Device               device                 1    ip      /],
  [qw/DeviceModule         modules                *    ip      /])

->Association(
  [qw/Device               device                 1    ip      /],
  [qw/DevicePower          power_modules          *    ip      /])

->Association(
  [qw/Node                 ---                    1    active  /],
  [qw/NodeIp               ips                    *    active  /])

->Association(
  [qw/Device               device                 1    ip      /],
  [qw/DeviceIp             device_ips             *    ip      /])

->Association(
  [qw/DevicePortVlan       _2                     1    ip      /],
  [qw/DevicePort           port                   1    ip      /])

->Association(
  [qw/User                 ---                    1    username/],
  [qw/Virtual::UserRole    roles                  *    username/])

->Association(
  [qw/Node                 _3                     1    switch  /],
  [qw/DevicePort           device_port            0..1 ip      /])

->Association(
  [qw/DevicePort           _4                     1    ip      /],
  [qw/DevicePort           agg_master             0..1 ip      /])

->Association(
  [qw/NodeIp               _2                     1    mac     /],
  [qw/NodeIp               node_ips               *    mac     /])

->Association(
  [qw/NodeNbt              _3                     1    active  /],
  [qw/NodeIp               nodeips                *    active  /])

->Association(
  [qw/DevicePortWireless   wireless               0..1 ip      /],
  [qw/DevicePort           port                   1    ip      /])

->Association(
  [qw/Device               _2                     1    ip      /],
  [qw/DevicePortPower      powered_ports          1..* ip      /])

->Association(
  [qw/Device               device                 1    ip      /],
  [qw/DevicePortWireless   wireless_ports         1..* ip      /])

->Association(
  [qw/Device               ---                    1    ip      /],
  [qw/Community            community              0..1 ip      /])

->Association(
  [qw/DevicePort           ---                    1    ip      /],
  [qw/Virtual::ActiveNodeWithAge active_nodes_with_age  *    switch  /])

->Association(
  [qw/Node                 ---                    1    switch  /],
  [qw/DevicePortWireless   wireless_port          0..1 ip      /])

->Association(
  [qw/DevicePort           ---                    1    port    /],
  [qw/Virtual::ActiveNode  active_nodes           *    port    /])

->Association(
  [qw/DevicePortSsid       ssid                   0..1 port    /],
  [qw/DevicePort           port                   1    port    /])

->Association(
  [qw/Device               _2                     1    ip      /],
  [qw/DevicePortProperties properties_ports       1..* ip      /])

->Association(
  [qw/DevicePort           device_port            1    ip      /],
  [qw/DeviceIp             _5                     1    ip      /])

->Association(
  [qw/Oui                  oui                    0..1 oui     /],
  [qw/Node                 ---                    1    oui     /])

->Association(
  [qw/Device               device                 1    ip      /],
  [qw/DevicePortSsid       ssids                  1..* ip      /])

;

#---------------------------------------------------------------------#
#                             COLUMN TYPES                            #
#---------------------------------------------------------------------#
# App::Netdisco::AutoCRUD::Schema->ColumnType(ColType_Example =>
#   fromDB => sub {...},
#   toDB   => sub {...});

# App::Netdisco::AutoCRUD::Schema::SomeTable->ColumnType(ColType_Example =>
#   qw/column1 column2 .../);



1;
