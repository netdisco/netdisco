#!/usr/bin/env perl

# The CSV header loops settings.port_columns; the body pushes values from a
# hand written IF per column. Nothing ties the two lists together, so a column
# with a header and no body branch shifts every later column up one position
# and mislabels the data with no error anywhere. This asserts the two lists
# are the same length with every column enabled.

use strict;
use warnings;

use Test::More 0.88;
use Text::CSV ();
use YAML::XS ();
use lib 'xt/lib';
use Test::Netdisco::Snapshot 'render_template';

# Rebuilt from the shipped config the way Web.pm builds it, rather than
# hardcoded, so a column added later with no CSV branch is caught here.
my $config = YAML::XS::LoadFile('share/config.yml');
my $device_ports = $config->{sidebar_defaults}->{device_ports};
my @port_columns =
  sort { $a->{idx} <=> $b->{idx} }
  map  {{ name => $_, %{ $device_ports->{$_} } }}
  grep { $_ =~ m/^c_/ } keys %$device_ports;

my @COLUMNS = grep { $_ ne 'c_admin' && $_ ne 'c_links' }
  map { $_->{name} } @port_columns;

# Every field the CSV body reads, so no branch short circuits on undef and
# silently pushes nothing.
my $row = {
  port => 'GigabitEthernet0/1', descr => 'uplink', up => 'up', up_admin => 'up',
  type => 'ethernetCsmacd', ifindex => 1, lastchange_stamp => '2026-01-01 00:00:00',
  name => 'uplink', filtered_tags => ['a','b'], speed_admin => '1 Gbps',
  speed => '1 Gbps', duplex_admin => 'full', duplex => 'full', error_disable_cause => '',
  mac => '00:00:00:00:00:01', mtu => 1500, vlan => 10,
  stp => 'forwarding', remote_ip => '', remote_dns => '',
  pae_authconfig_port_control => '', pae_authconfig_state => '',
  pae_authconfig_port_status => '', pae_authsession_user => '',
  pae_authsession_mab => '', pae_last_eapol_frame_source => '',
  ssid => [ { ssid => 'CORP' }, { ssid => 'GUEST' } ],
  power => undef,
};

my %params = map {; $_ => 'on' } @COLUMNS;

my ($csv, $error) = render_template('ajax/device/ports_csv.tt', {
  settings => { port_columns => \@port_columns },
  results  => [ $row ],
  params   => \%params,
  vlans    => {},
  device   => { ip => '192.0.2.1' },
  nodes    => 'active_nodes',
  ips      => 'ips',
});

is $error, undef, 'template renders without error';

my @lines = grep { length } split /\r?\n/, $csv;

# Counting commas would miscount the c_ssid field, whose value is itself a
# comma-joined list and so arrives quoted. Text::CSV counts fields.
my $parser = Text::CSV->new({ binary => 1 });
$parser->parse($lines[0]) or die 'failed to parse header line: ' . $parser->error_diag;
my @headers = $parser->fields;
$parser->parse($lines[1]) or die 'failed to parse data line: ' . $parser->error_diag;
my @data = $parser->fields;

is scalar(@data), scalar(@headers),
  'every CSV header has a matching value field with all columns enabled';

done_testing;
