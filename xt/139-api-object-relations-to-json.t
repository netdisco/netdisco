#!/usr/bin/env perl

# The /api/v1/object/device/... routes in Web/API/Objects.pm return each
# related row through TO_JSON, so every class they reach must have it.
# Several virtual result classes do not, which is fine until a route uses one.

use strict;
use warnings;

use Test::More 0.88;
use App::Netdisco::DB;

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  App::Netdisco::DB->clone;
};

my %routes = (
  Device => [qw/device_ips vlans ports modules port_vlans wireless_ports ssids powered_ports/],
  DevicePort => [qw/nodes active_nodes nodes_with_age active_nodes_with_age port_vlans logs ssid
                    power properties wireless agg_master last_node/],
);

subtest 'api_object_relations__every_routed_relation__class_has_TO_JSON' => sub {
  foreach my $source (sort keys %routes) {
    foreach my $rel (@{ $routes{$source} }) {
      my $class = $schema->source($source)->related_class($rel);
      ok($class->can('TO_JSON'), "$source $rel ($class)");
    }
  }
};

subtest 'last_node__new_row__serializes_with_TO_JSON' => sub {
  my $row = $schema->resultset('Virtual::LastNode')->new_result({ mac => '00:11:22:33:44:55' });
  my $json = eval { $row->TO_JSON };
  is(ref $json, 'HASH', 'TO_JSON returns a hash') or diag $@;
};

done_testing;
