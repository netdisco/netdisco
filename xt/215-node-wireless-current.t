#!/usr/bin/env perl

# wireless_current compares against the node's own device. Naming a joined
# "device" alias instead made every query without that alias fail in
# PostgreSQL ("missing FROM-clause entry"). These assert the generated SQL;
# no database needed.

use strict;
use warnings;

use Test::More 0.88;
use App::Netdisco::DB;

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $s = App::Netdisco::DB->clone;
  $s->storage_type('::DBI::Pg');
  $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $s;
};

sub sql_for {
  my ($rs) = @_;
  return ${ $rs->as_query }->[0];
}

subtest 'wirelessCurrent__joined_from_node_without_device__reads_the_node_switch' => sub {
  my $sql = sql_for($schema->resultset('Node')->search_rs({},
    { join => 'wireless_current', '+select' => ['wireless_current.ssid'] }));
  like($sql, qr/\(SELECT last_macsuck FROM device WHERE device\.ip = me\.switch\)/,
    'compares against the device of the node row');
  unlike($sql, qr/>=\s*device\.last_macsuck/, 'names no outer device alias');
};

subtest 'wirelessCurrent__joined_through_device_port__uses_the_node_alias' => sub {
  my $sql = sql_for($schema->resultset('DevicePort')->search_rs({},
    { join => { nodes => 'wireless_current' }, '+select' => ['wireless_current.ssid'] }));
  like($sql, qr/device\.ip = nodes\.switch\)/, 'reads switch from the joined node alias');
};

done_testing;
