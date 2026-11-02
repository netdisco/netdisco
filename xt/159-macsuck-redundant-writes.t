#!/usr/bin/env perl

use strict;
use warnings;

# macsuck rewrote rows that did not change: the freshness archive set
# active = false again on every stale row already archived, and is_uplink
# was written true once per MAC seen through a port (and per MAC on a LAG
# member, to its parent) even when the port was already an uplink. Each of
# those is a new row version.
#
# Only the database edges are faked: the schema, the device port rows, and
# the lookup of which MACs belong to devices.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use Dancer ':tests';
use App::Netdisco::Worker::Plugin::Macsuck::Nodes;

set logger => 'null';

my $NODES = 'App::Netdisco::Worker::Plugin::Macsuck::Nodes';
my (@searched, @port_updates, $port_macs);

package FakeNodes;
sub new       { return bless {}, $_[0] }
sub resultset { return $_[0] }
sub search    { push @searched, $_[1]; return $_[0] }
sub update    { return 3 }

package FakePort;
sub new { my ($class, %col) = @_; return bless {%col}, $class }
sub port   { $_[0]{port} }
sub update {
  my ($self, $set) = @_;
  push @port_updates, [$self->{port}, $set];
  $self->{$_} = $set->{$_} for keys %$set;
  return $self;
}
for my $col (qw/is_uplink neighbor remote_ip remote_id remote_type slave_of is_master/) {
  no strict 'refs';
  *{"FakePort::$col"} = sub { $_[0]{$col} };
}

package FakeDevice;
sub new { return bless {}, $_[0] }
sub ip  { '192.0.2.10' }

package main;

{
  no warnings 'redefine';
  no strict 'refs';
  *{"${NODES}::schema"} = sub { FakeNodes->new };
  *{"${NODES}::get_port_macs"} = sub { $port_macs };
}

my $device = FakeDevice->new;
my ($mac_a, $mac_b) = ('00:11:22:33:44:01', '00:11:22:33:44:02');

sub run_sanity {
  my ($cache, %ports) = @_;
  @port_updates = ();
  $NODES->can('sanity_macs')->($device, $cache, \%ports);
  return scalar @port_updates;
}

subtest 'archive_stale_nodes__search__filters_active' => sub {
  set node_freshness => 60;
  @searched = ();
  ok(my $archive = $NODES->can('archive_stale_nodes'), 'defined') or return;
  my $archived = $archive->($device, 'LOCALTIMESTAMP');
  is($archived, 3, 'returns the update count');
  is(scalar @searched, 1, 'one search');
  is($searched[0]{switch}, '192.0.2.10');
  is($searched[0]{-bool}, 'active', 'only active rows');
  ok(exists $searched[0]{time_last}, 'time_last bound');
};

subtest 'archive_stale_nodes__no_freshness__does_nothing' => sub {
  set node_freshness => 0;
  @searched = ();
  ok(my $archive = $NODES->can('archive_stale_nodes'), 'defined') or return;
  is($archive->($device, 'LOCALTIMESTAMP'), 0);
  is(scalar @searched, 0);
};

subtest 'sanity_macs__port_already_uplink__no_update' => sub {
  $port_macs = { $mac_a => '192.0.2.99' };
  my $port = FakePort->new(port => 'Gi1', is_uplink => 1, remote_ip => '192.0.2.99');
  is(run_sanity({ 0 => { Gi1 => { $mac_a => 1 } } }, Gi1 => $port), 0);

  $port = FakePort->new(port => 'Gi1', is_uplink => 0, remote_ip => '192.0.2.99');
  is(run_sanity({ 0 => { Gi1 => { $mac_a => 1 } } }, Gi1 => $port), 1, 'set when not yet an uplink');
};

subtest 'sanity_macs__two_macs_one_port__one_update' => sub {
  set macsuck_bleed => 1;
  $port_macs = { $mac_a => '192.0.2.99', $mac_b => '192.0.2.98' };
  my $port = FakePort->new(port => 'Gi1', is_uplink => 0);
  is(run_sanity({ 0 => { Gi1 => { $mac_a => 1, $mac_b => 1 } } }, Gi1 => $port), 1);
  set macsuck_bleed => 0;
};

subtest 'sanity_macs__lag_parent_already_uplink__no_update' => sub {
  $port_macs = {};
  my %ports = (
    Gi2 => FakePort->new(port => 'Gi2', is_uplink => 0, slave_of => 'Po1'),
    Po1 => FakePort->new(port => 'Po1', is_uplink => 1, is_master => 0),
  );
  is(run_sanity({ 0 => { Gi2 => { $mac_a => 1 } } }, %ports), 0);

  $ports{Po1} = FakePort->new(port => 'Po1', is_uplink => 0, is_master => 0);
  is(run_sanity({ 0 => { Gi2 => { $mac_a => 1 } } }, %ports), 1, 'set when not yet an uplink');
};

done_testing;
