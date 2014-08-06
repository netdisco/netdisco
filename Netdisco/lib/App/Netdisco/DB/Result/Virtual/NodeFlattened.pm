package App::Netdisco::DB::Result::Virtual::NodeFlattened;

use strict;
use warnings;

use utf8;
use base 'App::Netdisco::DB::Result::Node';

__PACKAGE__->load_components('Helper::Row::SubClass');
__PACKAGE__->subclass;

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');
__PACKAGE__->table('node_flattened');
__PACKAGE__->result_source_instance->is_virtual(1);
__PACKAGE__->result_source_instance->view_definition(<<'ENDSQL');
SELECT DISTINCT ON (n.mac,
                    n.port) n.*,

  (SELECT array_agg(n2.vlan)
   FROM node n2
   WHERE n2.port = n.port
     AND n2.mac = n.mac) AS vlans,

  (SELECT array_agg(ip)
   FROM
     (SELECT ni.ip
      FROM node_ip ni
      WHERE ni.mac = n.mac
      ORDER BY ni.ip) AS tab) AS ip,

  (SELECT array_agg(dns)
   FROM
     (SELECT ni.dns
      FROM node_ip ni
      WHERE ni.mac = n.mac
      ORDER BY ni.ip) AS tab) AS dns,

  (SELECT array_agg(active)
   FROM
     (SELECT ni.active
      FROM node_ip ni
      WHERE ni.mac = n.mac
      ORDER BY ni.ip) AS tab) AS ip_active,

  (SELECT array_agg(w.ssid)
   FROM node_wireless w
   WHERE w.mac = n.mac) AS ssids,
                            nb.nbname,
                            nb.domain,
                            nb.nbuser,
                            nb.ip AS nb_ip,
                            oui.abbrev
FROM node n
LEFT JOIN node_nbt nb ON nb.mac = n.mac
LEFT JOIN oui oui ON oui.oui = n.oui
WHERE n.switch = ?
ENDSQL

__PACKAGE__->add_columns(
  "vlans",
  { data_type => "integer[]", is_nullable => 1 },
  "ip",
  { data_type => "inet[]", is_nullable => 1 },
  "dns",
  { data_type => "text[]", is_nullable => 1 },
  "ip_active",
  { data_type => "boolean[]", is_nullable => 1 },
  "ssids",
  { data_type => "text[]", is_nullable => 1 },
  "nbname",
  { data_type => "text", is_nullable => 1 },
  "domain",
  { data_type => "text", is_nullable => 1 },
  "nbuser",
  { data_type => "text", is_nullable => 1 },
  "nb_ip",
  { data_type => "inet[]", is_nullable => 1 },
  "abbrev",
  { data_type => "text", is_nullable => 1 },
);

__PACKAGE__->belongs_to( device_port => 'App::Netdisco::DB::Result::Virtual::DevicePortFlattened',
  { 'foreign.ip' => 'self.switch', 'foreign.port' => 'self.port' },
  { join_type => 'LEFT' }
);

1;
