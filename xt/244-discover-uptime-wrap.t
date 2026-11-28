#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::DB::Upsert ();
use App::Netdisco::Backend::Job;
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Worker::Plugin::Discover::Properties ();
use App::Netdisco::Worker::Plugin::Discover::Properties::Tags ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# #1858: a single port whose ifLastChange was ahead of sysUpTime set a
# 2**32 uptime wrap that snmpEngineTime did not confirm, and only the ports
# checked after it had the wrap added to their last change. The examples are
# the reporter's: a Catalyst 9300 and a 9200CX with a row that has no
# ifDescr and no ifType, and a Nexus whose loopbacks report a change from
# before sysUpTime started. The Properties port worker runs for real, with
# SNMP and storage stubbed as in xt/172-discover-device-port-upsert.t.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

config->{'device_auth'} = [{driver => 'snmp'}];
config->{'enable_field_protection'} = 0;
config->{'enable_incomplete_walk_protection'} = 1;
config->{'ignore_deviceports'} = [];
config->{'dns'}->{'no'} = ['0.0.0.0/0'];

package FakeSNMP;
our $AUTOLOAD;
{ package NoopTagsSchema; sub resultset { return $_[0] } sub search { return $_[0] } sub update { return 0 } }

sub new { my ($class, %vals) = @_; return bless { walk_failures => [], %vals }, $class; }
sub walk_failures { $_[0]{walk_failures} }
sub walk_status { $_[0]{walk_status}{$_[1]} }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  if (my $failure = delete $self->{fail_on_read}{$method}) {
    push @{ $self->{walk_failures} }, $failure;
    $self->{walk_status}{$method} = $failure;
  }
  return unless exists $self->{$method};
  return $self->{$method};
}

package FakeRows;
sub new { my ($class, @rows) = @_; return bless { rows => [@rows] }, $class; }
sub reset { return $_[0] }
sub all { return @{ $_[0]->{rows}} }

package FakeLockedRow;
sub new { return bless {}, shift }
sub first { return $_[0] }

package FakeSchema;
sub txn_do { my ($self, $code) = @_; return $code->() }
sub resultset { my ($self, $name) = @_; return App::Netdisco::DB->resultset($name) }

package main;

my $WRAP = 2**32;
my $DAY  = 100 * 86400;

my %device_cols = (
  ip => '192.0.2.1', uptime => 900, description => 'desc', name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', chassis_id => 'chassis1', contact => '',
  location => 'Room A', num_ports => 2, snmp_class => 'SNMP::Info::Layer2',
  snmp_engineid => '', custom_fields => '{}', snmp_ver => 2,
);

my %base_snmp = (
  vtp_d_name => undef, vtp_d_mode => undef,
  snmp_ver => 2, description => 'desc', name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', serial1 => 'chassis1', contact => '', location => 'Room A',
  class => 'SNMP::Info::Layer2', snmpEngineID => '', id => undef,
  i_ignore => {}, agg_ports => {}, i_subinterfaces => {},
);

my @upserts;

# each port is [ ifIndex, ifDescr, ifType, ifLastChange ]; a port with no
# ifDescr is named by its ifIndex, as SNMP::Info's interfaces method does
sub run_discover {
  my (%args) = @_;
  delete @{ vars() }{qw/device_changed new_device device_ports hook_data timestamp incomplete_walks/};
  @upserts = ();

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_discover'} = 0;

  my @ports = @{ $args{ports} };
  my $fake_snmp = FakeSNMP->new(%base_snmp,
    uptime => $args{uptime}, load_uptime => $args{uptime},
    (exists $args{engine} ? (snmpEngineTime => $args{engine}) : ()),
    fail_on_read => ($args{fail_on_read} || {}),
    ports => scalar @ports,
    interfaces    => { map { $_->[0] => ($_->[1] // $_->[0]) } @ports },
    i_description => { map { $_->[0] => $_->[1] } @ports },
    i_type        => { map { $_->[0] => $_->[2] } @ports },
    i_lastchange  => { map { $_->[0] => $_->[3] } @ports },
  );
  my $search = DBIx::Class::ResultSet->can('search');
  no warnings 'once';

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::Tags::schema
    = sub { return bless {}, 'NoopTagsSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::warning = sub { };
  local *App::Netdisco::DB::Result::Device::ports = sub { return FakeRows->new };
  local *App::Netdisco::DB::Result::Device::device_ips = sub { return FakeRows->new };
  local *App::Netdisco::DB::Result::Device::update = sub { return $_[0] };
  local *App::Netdisco::DB::Result::Device::update_or_insert = sub { return $_[0] };
  local *App::Netdisco::DB::ResultSet::Device::search = sub {
    my ($rs, $cond, $attrs) = @_;
    return $search->(@_) unless $attrs and $attrs->{for};
    return FakeLockedRow->new;
  };
  local *App::Netdisco::DB::ResultSet::DevicePort::txn_do_locked = sub { return $_[-1]->() };
  local *App::Netdisco::DB::Upsert::upsert = sub {
    my ($rs, $rows) = @_;
    push @upserts, [ $rs->result_source->source_name, $rows ];
    return 0;
  };
  local *App::Netdisco::DB::Upsert::remove_unseen = sub { return 0 };
  local *App::Netdisco::DB::ResultSet::DevicePort::retire_ports = sub { return 0 };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'discover::properties',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return ($job, $device);
}

sub stored_lastchange {
  my ($call) = grep { $_->[0] eq 'DevicePort' } @upserts;
  return {} unless $call;
  return { map { $_->{port} => $_->{lastchange} } @{ $call->[1] } };
}

# real ports on either side of the placeholder row in string order of
# ifIndex, each changed a day before the poll
sub catalyst_ports {
  my ($uptime, $placeholder_index, $placeholder_lc) = @_;
  return [
    (map { [ $_, "Port$_", 'ethernetCsmacd', $uptime - $DAY ] }
      grep { $_ != $placeholder_index } 1, 2, 10, 100, 200),
    [ $placeholder_index, undef, undef, $placeholder_lc ],
  ];
}

subtest 'uptime_wrap__catalyst9300_placeholder_row_engine_agrees__no_wrap_and_every_port_kept' => sub {
  my $uptime = 110604316;
  my $ports = catalyst_ports($uptime, 2, 858993459);
  my ($job, $device) = run_discover(uptime => $uptime, engine => 1105638, ports => $ports);
  is $job->status, 'done', 'job completes';
  is $device->uptime, $uptime, 'uptime is not wrapped';
  my $lastchange = stored_lastchange();
  is $lastchange->{"Port$_"}, $uptime - $DAY, "Port$_ keeps its last change" for 1, 10, 100, 200;
  is $lastchange->{2}, 0, 'placeholder row stored with last change 0';
};

subtest 'uptime_wrap__catalyst9200cx_placeholder_row_engine_agrees__no_wrap' => sub {
  my $uptime = 7480820;
  my $ports = catalyst_ports($uptime, 1, 1228472500);
  my ($job, $device) = run_discover(uptime => $uptime, engine => 74654, ports => $ports);
  is $device->uptime, $uptime, 'uptime is not wrapped';
  my $lastchange = stored_lastchange();
  is $lastchange->{"Port$_"}, $uptime - $DAY, "Port$_ keeps its last change" for 2, 10, 100, 200;
  is $lastchange->{1}, 0, 'placeholder row stored with last change 0';
};

subtest 'uptime_wrap__nexus_lastchange_before_agent_start_engine_agrees__stored_zero' => sub {
  my $uptime = 1210444141;
  my $ports = [
    [ 1, 'Ethernet1/1', 'ethernetCsmacd', $uptime - $DAY ],
    [ 2, 'loopback0', 'softwareLoopback', 4294908803 ],
    [ 3, 'port-channel1', 'ieee8023adLag', 4294908803 ],
    [ 4, 'Ethernet1/2', 'ethernetCsmacd', $uptime - $DAY ],
  ];
  my ($job, $device) = run_discover(uptime => $uptime, engine => 12104442, ports => $ports);
  is $device->uptime, $uptime, 'uptime is not wrapped';
  my $lastchange = stored_lastchange();
  is $lastchange->{'Ethernet1/1'}, $uptime - $DAY, 'port before the loopback kept';
  is $lastchange->{'Ethernet1/2'}, $uptime - $DAY, 'port after the loopback kept';
  is $lastchange->{loopback0}, 0, 'loopback stored with last change 0';
  is $lastchange->{'port-channel1'}, 0, 'port-channel stored with last change 0';
};

subtest 'uptime_wrap__engine_agrees_with_one_wrap__every_port_corrected' => sub {
  my $uptime = 50000000;
  my $ports = [
    [ 1, 'Port1', 'ethernetCsmacd', $uptime - $DAY ],
    [ 2, 'Port2', 'ethernetCsmacd', 4000000000 ],
    [ 3, 'Port3', 'ethernetCsmacd', $uptime - $DAY ],
    [ 4, 'Port4', 'ethernetCsmacd', 20000 ],
  ];
  my ($job, $device) = run_discover(uptime => $uptime,
    engine => int(($WRAP + $uptime) / 100), ports => $ports);
  is $device->uptime, $uptime + $WRAP, 'uptime wrapped once';
  my $lastchange = stored_lastchange();
  is $lastchange->{Port1}, $uptime - $DAY + $WRAP, 'change after the wrap corrected';
  is $lastchange->{Port3}, $uptime - $DAY + $WRAP, 'second change after the wrap corrected';
  is $lastchange->{Port2}, 4000000000, 'change before the wrap kept';
  is $lastchange->{Port4}, 20000, 'change within 5 minutes of boot kept';
};

subtest 'uptime_wrap__engine_lags_sysuptime_across_a_wrap__counts_the_wrap' => sub {
  my $uptime = 20000;
  my $ports = [ [ 1, 'Port1', 'ethernetCsmacd', 10000 ] ];
  my ($job, $device) = run_discover(uptime => $uptime,
    engine => int(($WRAP + $uptime - 40500) / 100), ports => $ports);
  is $device->uptime, $uptime + $WRAP, 'uptime wrapped once though engine time has not';
};

subtest 'uptime_wrap__no_engine_time_real_port_ahead__wrap_applied_to_every_port' => sub {
  my $uptime = 50000000;
  my $ports = [
    [ 1, 'Port1', 'ethernetCsmacd', $uptime - $DAY ],
    [ 2, 'Port2', 'ethernetCsmacd', 4000000000 ],
    [ 3, 'Port3', 'ethernetCsmacd', $uptime - $DAY ],
  ];
  my ($job, $device) = run_discover(uptime => $uptime, ports => $ports);
  is $device->uptime, $uptime + $WRAP, 'uptime wrapped';
  my $lastchange = stored_lastchange();
  is $lastchange->{Port1}, $uptime - $DAY + $WRAP, 'port checked before the trigger corrected';
  is $lastchange->{Port3}, $uptime - $DAY + $WRAP, 'port checked after the trigger corrected';
  is $lastchange->{Port2}, 4000000000, 'trigger kept';
};

subtest 'uptime_wrap__no_engine_time_lastchange_within_boot_skew__no_wrap_and_kept' => sub {
  my $uptime = 50000;
  my $ports = [ [ 1, 'Port1', 'ethernetCsmacd', $uptime + 10000 ] ];
  my ($job, $device) = run_discover(uptime => $uptime, ports => $ports);
  is $device->uptime, $uptime, 'uptime is not wrapped';
  is stored_lastchange()->{Port1}, $uptime + 10000, 'last change kept';
};

subtest 'uptime_wrap__engine_time_disagrees__falls_back_to_lastchange_check' => sub {
  my $uptime = 50000000;
  my $ports = [
    [ 1, 'Port1', 'ethernetCsmacd', $uptime - $DAY ],
    [ 2, 'Port2', 'ethernetCsmacd', 4000000000 ],
  ];
  my ($job, $device) = run_discover(uptime => $uptime, engine => 5, ports => $ports);
  is $device->uptime, $uptime + $WRAP, 'uptime wrapped by the lastchange check';
  is stored_lastchange()->{Port1}, $uptime - $DAY + $WRAP, 'port corrected';
};

done_testing;
