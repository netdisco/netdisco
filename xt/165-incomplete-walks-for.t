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
use App::Netdisco::Util::SNMP qw/walk_mark incomplete_walks_for
  incomplete_walk_level incomplete_walk_message/;
use App::Netdisco::Worker::Plugin::Discover::Properties ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The Properties worker tests stub SNMP and storage as xt/51-updated-device-hook.t
# does. The unit tests use a fake SNMP::Info that keeps the two walk records
# the installed SNMP::Info (3.979000) lacks.

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

package RecordingSNMP; # keeps walk_failures and walk_status
sub new { my ($class, %vals) = @_; return bless { walk_failures => [], walk_status => {}, %vals }, $class; }
sub walk_failures { $_[0]{walk_failures} }
sub walk_status { $_[0]{walk_status}{$_[1]} }

package PlainSNMP; # an SNMP::Info with no walk record
sub new { return bless {}, shift }

package FakeSNMP;
our $AUTOLOAD;
sub new { my ($class, %vals) = @_; return bless {%vals}, $class; }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  return $self->{$method};
}
sub walk_failures { $_[0]{walk_failures} ||= [] }
# the walk records its failure while it runs, as SNMP::Info does
sub interfaces {
  my $self = shift;
  push @{ $self->walk_failures }, @{ $self->{interfaces_fails} || [] };
  return $self->{interfaces};
}

package FakePortsRS;
sub new { my ($class, @rows) = @_; return bless { rows => [@rows] }, $class; }
sub reset { return $_[0] }
sub all { return @{ $_[0]->{rows} } }

package FakeLockedRow;
sub new { return bless {}, shift }
sub first { return $_[0] }

package FakeSchema;
sub txn_do { my ($self, $code) = @_; return $code->() }
sub resultset { my ($self, $name) = @_; return App::Netdisco::DB->resultset($name) }

package main;

sub outcome {
  my ($method, %extra) = @_;
  return { method => $method, leaf => "MIB::$method", reason => 'timeout',
           rows => 1, walk => 'bulkwalk', complete => 0, %extra };
}

my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });
my $other_device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.2' });

subtest 'incomplete_walks_for__failure_since_mark__returned' => sub {
  my $snmp = RecordingSNMP->new;
  my $mark = walk_mark($snmp);
  my $failure = outcome('i_index');
  push @{ $snmp->walk_failures }, $failure;
  is_deeply [ incomplete_walks_for($device, $snmp, $mark) ], [ $failure ];
};

subtest 'incomplete_walks_for__failure_before_mark_on_named_method__returned' => sub {
  my $failure = outcome('ip_index');
  my $snmp = RecordingSNMP->new(
    walk_failures => [ $failure ], walk_status => { ip_index => $failure });
  my $mark = walk_mark($snmp);
  is_deeply [ incomplete_walks_for($device, $snmp, $mark, 'ip_index') ], [ $failure ];
};

subtest 'incomplete_walks_for__failure_before_mark_on_other_method__not_returned' => sub {
  my $failure = outcome('i_index');
  my $snmp = RecordingSNMP->new(
    walk_failures => [ $failure ], walk_status => { i_index => $failure });
  my $mark = walk_mark($snmp);
  is_deeply [ incomplete_walks_for($device, $snmp, $mark, 'ip_index') ], [];
};

subtest 'incomplete_walks_for__named_method_failed_then_succeeded__not_returned' => sub {
  my $snmp = RecordingSNMP->new(
    walk_failures => [ outcome('ip_index') ],
    walk_status => { ip_index => outcome('ip_index', complete => 1) });
  is_deeply [ incomplete_walks_for($device, $snmp, walk_mark($snmp), 'ip_index') ], [];
};

subtest 'incomplete_walks_for__interfaces_named__includes_job_record' => sub {
  my $failure = outcome('i_index');
  vars->{'incomplete_walks'}{ $device->ip }{'interfaces'} = [ $failure ];
  my $snmp = RecordingSNMP->new;

  is_deeply [ incomplete_walks_for($device, $snmp, 0, 'interfaces') ], [ $failure ],
    'record included for the named device';
  is_deeply [ incomplete_walks_for($other_device, $snmp, 0, 'interfaces') ], [],
    'record under a different device IP not included';
  is_deeply [ incomplete_walks_for($device, $snmp, 0, 'ip_index') ], [],
    'record not included when interfaces is not named';
  delete vars->{'incomplete_walks'};
};

subtest 'incomplete_walks_for__same_outcome_twice__returned_once' => sub {
  my $failure = outcome('i_index');
  vars->{'incomplete_walks'}{ $device->ip }{'interfaces'} = [ $failure ];
  my $snmp = RecordingSNMP->new(
    walk_failures => [ $failure ], walk_status => { interfaces => $failure });
  is_deeply [ incomplete_walks_for($device, $snmp, 0, 'interfaces') ], [ $failure ];
  delete vars->{'incomplete_walks'};
};

subtest 'incomplete_walks_for__setting_off__returns_nothing' => sub {
  local config->{'enable_incomplete_walk_protection'} = 0;
  my $snmp = RecordingSNMP->new(walk_failures => [ outcome('i_index') ]);
  is_deeply [ incomplete_walks_for($device, $snmp, 0) ], [];
};

subtest 'incomplete_walks_for__snmp_without_walk_record__returns_nothing' => sub {
  vars->{'incomplete_walks'}{ $device->ip }{'interfaces'} = [ outcome('i_index') ];
  is_deeply [ incomplete_walks_for($device, PlainSNMP->new, 0, 'interfaces') ], [];
  delete vars->{'incomplete_walks'};
};

subtest 'incomplete_walks_for__absent_reason_marked_complete__returned' => sub {
  my $absent = outcome('ip_index', complete => 1, reason => 'absent');
  my $snmp = RecordingSNMP->new(walk_status => { ip_index => $absent, ip_table => outcome('ip_table', complete => 1, reason => 'ok') });
  is_deeply [ incomplete_walks_for($device, $snmp, 0, 'ip_index', 'ip_table') ], [ $absent ];
};

subtest 'incomplete_walk_level__absent_among_outcomes__error' => sub {
  is incomplete_walk_level(outcome('ip_table'),
    outcome('ip_index', complete => 1, reason => 'absent')), 'error';
};

subtest 'incomplete_walk_level__cut_short_outcomes_only__info' => sub {
  is incomplete_walk_level(outcome('ip_index'), outcome('ip_table', reason => 'loop')), 'info';
};

subtest 'incomplete_walk_message__absent_outcome__names_the_mibs_to_check' => sub {
  my $message = incomplete_walk_message($device, 'device_ip',
    outcome('ip_index', complete => 1, reason => 'absent', rows => 0));
  like $message, qr/ip_index \(MIB::ip_index\) absent after 0 rows/;
  like $message, qr/could not translate .+ netdisco-mibs .+ mibhome/;
};

subtest 'incomplete_walk_message__cut_short_outcome__no_mibs_hint' => sub {
  unlike incomplete_walk_message($device, 'device_ip', outcome('ip_index')), qr/netdisco-mibs/;
};

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

my %device_cols = (
  ip => '192.0.2.1', uptime => 900, description => 'desc', name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', chassis_id => 'chassis1', contact => '',
  location => 'Room A', num_ports => 2, snmp_class => 'SNMP::Info::Layer2',
  snmp_engineid => '', custom_fields => '{}', snmp_ver => 2,
);

my %base_snmp = (
  vtp_d_name => undef, vtp_d_mode => undef,
  snmp_ver => 2, description => 'desc', uptime => 900, name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', serial1 => 'chassis1', contact => '', location => 'Room A',
  ports => 2, class => 'SNMP::Info::Layer2', snmpEngineID => '', id => undef,
  load_uptime => 900,
  interfaces => { 1 => 'Gi1/1', 2 => 'Gi1/2' },
  i_type => { 1 => '6', 2 => '6' }, i_ignore => {},
  i_description => { 1 => 'Gi1/1', 2 => 'Gi1/2' },
  agg_ports => {}, i_subinterfaces => {},
);

sub run_discover {
  my (%snmp) = @_;
  delete @{ vars() }{qw/device_changed new_device device_ports hook_data timestamp incomplete_walks/};

  no warnings 'once';
  my $discover_device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $discover_device->in_storage(1);
  $discover_device->{'_column_data'}{'since_last_discover'} = 0;

  my $fake_snmp = FakeSNMP->new(%base_snmp, %snmp);
  my $ports_rs = FakePortsRS->new;
  my $search = DBIx::Class::ResultSet->can('search');

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::DB::Result::Device::ports = sub { return $ports_rs };
  local *App::Netdisco::DB::Result::Device::device_ips = sub { return FakePortsRS->new };
  local *App::Netdisco::DB::Result::Device::update = sub { return $_[0] };
  local *App::Netdisco::DB::Result::Device::update_or_insert = sub { return $_[0] };
  local *App::Netdisco::DB::Upsert::upsert = sub { return 0 };
  local *App::Netdisco::DB::Upsert::remove_unseen = sub { return 0 };
  local *App::Netdisco::DB::ResultSet::DevicePort::retire_ports = sub { return 0 };
  local *App::Netdisco::DB::ResultSet::Device::search = sub {
    my ($rs, $cond, $attrs) = @_;
    return ($attrs and $attrs->{for}) ? FakeLockedRow->new : $search->(@_);
  };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $discover_device, action => 'discover::properties',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

subtest 'interfaces_worker__incomplete_interfaces_walk__records_it_for_the_job' => sub {
  my $earlier = outcome('uptime');
  my $failure = outcome('i_index', rows => 0);
  my $job = run_discover(
    walk_failures => [ $earlier ], interfaces_fails => [ $failure ]);

  is_deeply vars->{'incomplete_walks'}{'192.0.2.1'}{'interfaces'}, [ $failure ],
    'only the failure from the interfaces read is recorded';
  ok !$job->is_cancelled, 'discover behavior unchanged';
  is $job->status, 'done', 'the incomplete run completes';

  $job = run_discover();
  is_deeply vars->{'incomplete_walks'}{'192.0.2.1'}{'interfaces'}, [],
    'a complete walk records an empty list';
  is $job->status, 'done', 'the complete run completes';
};

done_testing;
