#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB; # fake device/deviceport rows
use App::Netdisco::Backend::Job;
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Worker::Plugin::Discover::Properties ();
use App::Netdisco::Worker::Plugin::Discover::Hooks ();
use aliased 'App::Netdisco::Worker::Status';

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# configure logging to force console output
my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# This exercises the real Discover::Properties and Discover::Hooks worker
# code (not a reimplementation of their logic) so that the
# updated_device_hook_ignored_fields diffing is genuinely tested. Both
# plugins normally need a live SNMP connection and a live Postgres, neither
# of which is available to xt/ tests (there is no DB service in CI), so
# below we stub the few points where they touch SNMP/storage and let
# everything else run for real. Overrides are installed with
# "local *Package::sub = sub {...}" AFTER the target package is `use`d
# above, because installing them first would just get clobbered when
# Module::Load::load'ing the real plugin during the job compiles its own
# sub/import into that same glob slot.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

config->{'device_auth'} = [{driver => 'snmp'}];
config->{'enable_field_protection'} = 0; # unrelated feature, keep it out of the way
config->{'ignore_deviceports'} = [];     # ditto - avoid its device_ips() DB lookup
config->{'dns'}->{'no'} = ['0.0.0.0/0']; # skip real DNS resolution of the alias worker

package FakeSNMP;
our $AUTOLOAD;
sub new { my ($class, %vals) = @_; return bless {%vals}, $class; }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  return $self->{$method};
}

package FakePortsRS; # stands in for a DBIC ResultSet of DevicePort rows
sub new { my ($class, @rows) = @_; return bless { rows => [@rows] }, $class; }
sub reset { return $_[0] }
sub all { return @{ $_[0]->{rows} } }
sub delete { return 0 }
sub populate { return 1 }

package FakeDevicePortRS; # only result_source (metadata) and locking are used
sub new { return bless {}, shift }
sub result_source { return App::Netdisco::DB->resultset('DevicePort')->result_source }
sub txn_do_locked { my ($self, $mode, $code) = @_; return $code->() }

package FakeSchema;
sub txn_do { my ($self, $code) = @_; return $code->() }
sub resultset {
  my ($self, $name) = @_;
  return FakeDevicePortRS->new if $name eq 'DevicePort';
  return App::Netdisco::DB->resultset($name);
}

package main;

# baseline "everything already matches" fixture: a discover of this device
# with this SNMP data should find zero meaningful changes
my %base_device_cols = (
  ip => '192.0.2.10', uptime => 900, description => 'desc', name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', chassis_id => 'chassis1', contact => '',
  location => 'Room A', num_ports => 1, snmp_class => 'SNMP::Info::Layer2',
  snmp_engineid => '', custom_fields => '{}', snmp_ver => 2,
);

my %base_snmp = (
  vtp_d_name => undef, vtp_d_mode => undef,
  snmp_ver => 2, description => 'desc', uptime => 900, name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', serial1 => 'chassis1', contact => '', location => 'Room A',
  ports => 1, class => 'SNMP::Info::Layer2', snmpEngineID => '', id => undef,
  load_uptime => 900,
  interfaces => { 1 => '1' },
  i_type => { 1 => '6' }, i_ignore => {}, i_description => { 1 => 'desc1' },
  i_mtu => { 1 => 1500 }, i_speed => { 1 => '1000000000' }, i_speed_admin => { 1 => '1000000000' },
  i_mac => { 1 => '00:11:22:33:44:55' }, i_up => { 1 => 'up' }, i_up_admin => { 1 => 'up' },
  i_name => { 1 => 'GigabitEthernet1/1' }, i_duplex => { 1 => 'full' }, i_duplex_admin => { 1 => 'full' },
  i_stp_state => { 1 => 'forwarding' }, i_vlan => { 1 => '10' }, i_lastchange => { 1 => 0 },
  agg_ports => {}, i_subinterfaces => {},
);

my %base_old_port = (
  ip => '192.0.2.10', port => '1', descr => 'desc1', up => 'up', up_admin => 'up',
  mac => '00:11:22:33:44:55', speed => '1000000000', speed_admin => '1000000000', mtu => 1500,
  name => 'GigabitEthernet1/1', duplex => 'full', duplex_admin => 'full', stp => 'forwarding',
  type => '6', vlan => '10', pvid => '10', has_subinterfaces => 'false', is_master => 'false',
  slave_of => undef, lastchange => 0, custom_fields => '{}',
);

# runs the real Discover::Properties early-phase workers for one device,
# with device- and port-level fixtures merged onto the matching baseline
# above, and returns whether vars->{device_changed} ended up set.
sub run_discover_properties {
  my (%opt) = @_;
  my %device_cols = (%base_device_cols, %{ $opt{'device'}    || {} });
  my %snmp_vals   = (%base_snmp,        %{ $opt{'snmp'}      || {} });
  my %old_port    = (%base_old_port,    %{ $opt{'old_port'}  || {} });

  delete @{ vars() }{qw/device_changed new_device device_ports hook_data timestamp/};

  local $CONFIG->{'updated_device_hook_ignored_fields'} = $opt{'ignored_fields'}
    if $opt{'ignored_fields'};

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);

  # since_last_discover is normally added as a virtual column by the
  # with_times() resultset modifier, which this directly-constructed row
  # never goes through - poke it in so the check-phase age comparison
  # (unrelated to this feature) doesn't die on a missing column
  $device->{'_column_data'}{'since_last_discover'} = 0;

  my $fake_snmp = FakeSNMP->new(%snmp_vals);
  my $old_ports_rs = FakePortsRS->new(
    App::Netdisco::DB->resultset('DevicePort')->new_result({ %old_port }),
  );

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::DB::Result::Device::ports = sub { return $old_ports_rs };
  local *App::Netdisco::DB::Result::Device::device_ips = sub { return FakePortsRS->new };
  no warnings 'once'; # these two globs are otherwise never referenced by name
  local *App::Netdisco::DB::Result::Device::update = sub { return $_[0] };
  local *App::Netdisco::DB::Result::Device::update_or_insert = sub { return $_[0] };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'discover::properties',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return ($job, (vars->{'device_changed'} ? 1 : 0));
}

# TESTS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# only uptime differs (a default-ignored device field, always dirty anyway
# via last_discover/num_ports) - nothing meaningful changed
{
  my ($job, $changed) = run_discover_properties(device => { uptime => 12345 });
  is($job->status, 'done', 'baseline discover completes');
  is($changed, 0, 'ignored-only device field change does not set device_changed');
}

# a real (non-ignored) device field changes
{
  my ($job, $changed) = run_discover_properties(
    device => { uptime => 12345, location => 'Room B' },
  );
  is($job->status, 'done', 'discover completes');
  is($changed, 1, 'non-ignored device field change sets device_changed');
}

# same change, but now configured to be ignored - updated_device_hook_ignored_fields
# for "device" is honoured
{
  my ($job, $changed) = run_discover_properties(
    device => { uptime => 12345, location => 'Room B' },
    ignored_fields => {
      device      => [qw/uptime last_discover num_ports location/],
      device_port => [qw/up up_admin lastchange/],
    },
  );
  is($job->status, 'done', 'discover completes');
  is($changed, 0, 'device field added to updated_device_hook_ignored_fields is suppressed');
}

# a real (non-ignored) port field changes
{
  my ($job, $changed) = run_discover_properties(old_port => { descr => 'old description' });
  is($job->status, 'done', 'discover completes');
  is($changed, 1, 'non-ignored device_port field change sets device_changed');
}

# same change, but now configured to be ignored - updated_device_hook_ignored_fields
# for "device_port" is honoured
{
  my ($job, $changed) = run_discover_properties(
    old_port => { descr => 'old description' },
    ignored_fields => {
      device      => [qw/uptime last_discover num_ports/],
      device_port => [qw/up up_admin lastchange descr/],
    },
  );
  is($job->status, 'done', 'discover completes');
  is($changed, 0, 'device_port field added to updated_device_hook_ignored_fields is suppressed');
}

# the shipped share/config.yml defaults ignore port up/up_admin state flaps
{
  my ($job, $changed) = run_discover_properties(
    old_port => { up => 'down', up_admin => 'down' },
  );
  is($job->status, 'done', 'discover completes');
  is($changed, 0, 'default config ignores device_port up/up_admin changes');
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Discover::Hooks: does the updated_device event actually get queued when
# device_changed is set? This is invoked directly (skipping the job Loader
# and Runner's namespace filtering) because the "late" phase hooks worker
# expects earlier phases to have already reported a status via
# $job->best_status, which a namespace-restricted job of only this one
# worker never provides.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

config->{'hooks'} = [
  { event => 'updated_device', type => 'exec', with => { cmd => '/bin/true' } },
  { event => 'new_device',     type => 'exec', with => { cmd => '/bin/true' } },
];

my @queued;
local *App::Netdisco::Worker::Plugin::Discover::Hooks::queue_hook = sub {
  my ($event, $conf) = @_;
  push @queued, $event;
  return 1;
};

sub run_hooks_worker {
  my (%flags) = @_;
  delete @{ vars() }{qw/device_changed new_device/};
  vars->{'device_changed'} = 1 if $flags{'device_changed'};
  vars->{'new_device'}     = 1 if $flags{'new_device'};

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.20' });
  $device->in_storage(1);

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'discover',
  });
  $job->enter_phase('early');
  $job->add_status(Status->done('setup ok'));
  $job->enter_phase('late');

  my $tree = vars->{'workers'}->{'discover'}->{'late'}->{'hooks'};
  my @workers = map { @{ $tree->{$_} } } sort { $a <=> $b } keys %$tree;
  $job->add_status($_->($job)) for @workers;

  return @queued;
}

@queued = ();
is_deeply([run_hooks_worker(device_changed => 1)], ['updated_device'],
  'updated_device hook queued when device_changed is set');

@queued = ();
is_deeply([run_hooks_worker(device_changed => 0)], [],
  'updated_device hook not queued when device_changed is unset');

@queued = ();
is_deeply([run_hooks_worker(new_device => 1)], ['new_device'],
  'new_device hook still queued independently of device_changed');

done_testing;
