#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once';

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Backend::Job;
use App::Netdisco::Worker::Plugin::Macsuck::Nodes ();

use Dancer qw/:moose :script !pass/;

# macsuck_no_unnamed skips VLANs with no name, such as the internal VLANs a
# Catalyst 6500 gives its routed ports, which have no SNMPv3 context and
# time out on every walk. The SNMP worker skipped them, but the store phase
# filtered the VLANs again with no names at all, so every VLAN looked
# unnamed and the job stored no MAC address but those on VLAN 0.
#
# Claims, kept apart:
#   - the store phase keeps the named VLANs the SNMP worker read;
#   - it drops the unnamed ones;
#   - with no names read (CLI, offline data, non-Cisco), macsuck_no_unnamed
#     has nothing to go on and drops nothing;
#   - an earlier job's names do not carry over;
#   - without macsuck_no_unnamed nothing changes.
#
# The SNMP worker's VLAN list is read from a fake SNMP::Info; the store
# worker runs for real, with its database writes replaced.

set logger => 'null';

package FakeSNMP;
sub new { my ($class, %m) = @_; bless {%m}, $class }
our $AUTOLOAD;
sub AUTOLOAD {
  my $self = shift;
  (my $m = $AUTOLOAD) =~ s/.*:://;
  return if $m eq 'DESTROY';
  return $self->{$m};
}

package FakeResultSet;
sub all { () }

package main;

my @stored;
{
  no warnings 'redefine';
  *App::Netdisco::Worker::Plugin::Macsuck::Nodes::store_node
    = sub { push @stored, $_[1] };
  *App::Netdisco::Worker::Plugin::Macsuck::Nodes::sanity_macs
    = sub { $_[1] };
  *App::Netdisco::Worker::Plugin::Macsuck::Nodes::archive_stale_nodes
    = sub { 0 };
}

sub store_worker {
  return (grep { ref }
    @{ vars->{'workers'}{'macsuck'}{'store'}{'nodes'}{0} || [] })[0];
}

my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });
$device->in_storage(1);

# VLAN 120 is named, 1168 is an internal VLAN with no name
my $snmp = FakeSNMP->new(
  cisco_comm_indexing => 1,
  i_vlan => { 1 => 120, 2 => 1168 },
  v_name => { 120 => 'users' },
);

# a MAC address of its own per VLAN: the store worker drops a VLAN 0 entry
# when the same MAC address is also on a numbered VLAN
sub fwtable {
  return { map { ($_ => { 'Gi1/1' => { sprintf('00:11:22:33:%02x:%02x',
                                               $_ >> 8, $_ & 255) => 1 } }) } @_ };
}

# the store worker, from after the main phase; $names is what the SNMP
# worker left (undef when it did not run)
sub stored_vlans {
  my ($names) = @_;
  @stored = ();
  vars->{'macsuck_vlan_names'} = $names;
  vars->{'fwtable'} = fwtable(0, 120, 1168);
  vars->{'device_ports'} = {};
  vars->{'timestamp'} = 'LOCALTIMESTAMP';
  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'macsuck' });
  no warnings 'redefine';
  local *App::Netdisco::Backend::Job::best_status = sub { 'info' };
  store_worker()->($job);
  return [ sort { $a <=> $b } @stored ];
}

ok store_worker(), 'the store worker is registered';

{
  local config->{'macsuck_no_unnamed'} = 1;

  my @walked = App::Netdisco::Worker::Plugin::Macsuck::Nodes::get_vlan_list(
    $snmp, $device);
  is_deeply \@walked, [120],
    'macsuckNoUnnamed__snmp_vlan_list__internal_vlan_not_walked';

  is_deeply stored_vlans(vars->{'macsuck_vlan_names'}), [0, 120],
    'macsuckNoUnnamed__store__named_vlan_kept_unnamed_dropped';

  is_deeply stored_vlans(undef), [0, 120, 1168],
    'macsuckNoUnnamed__store_without_names__nothing_dropped';
}

is_deeply stored_vlans({ 120 => 'users' }), [0, 120, 1168],
  'macsuckNoUnnamed__off__nothing_dropped';

{
  my $early = (grep { ref }
    @{ vars->{'workers'}{'macsuck'}{'early'}{'nodes'}{0} || [] })[0];
  no warnings 'redefine';
  local *App::Netdisco::DB::Result::Device::ports
    = sub { bless {}, 'FakeResultSet' };
  vars->{'macsuck_vlan_names'} = { 120 => 'users' };
  $early->(App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'macsuck' }));
  ok !defined vars->{'macsuck_vlan_names'},
    'macsuckNoUnnamed__early__names_of_earlier_job_cleared';
}

done_testing;
