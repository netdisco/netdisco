#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::DB::Upsert ();
use App::Netdisco::Backend::Job;
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Worker::Plugin::Discover::VLANs ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The VLANs worker runs for real with SNMP stubbed. upsert and remove_unseen
# are replaced by recorders, so no database is needed.

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
config->{'enable_incomplete_walk_protection'} = 1;

package FakeSNMP;
our $AUTOLOAD;
sub new { my ($class, %vals) = @_; return bless { walk_failures => [], %vals }, $class; }
sub walk_failures { $_[0]{walk_failures} }
sub walk_status { $_[0]{walk_status}{$_[1]} }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  # a failing walk records itself on its first read only, as a cached table does
  if (my $failure = delete $self->{fail_on_read}{$method}) {
    push @{ $self->{walk_failures} }, $failure;
    $self->{walk_status}{$method} = $failure;
  }
  return $self->{$method};
}

package FakeRows;
sub new { my ($class, @rows) = @_; return bless { rows => [@rows] }, $class; }
sub all { return @{ $_[0]->{rows}} }
sub search { return $_[0] }
sub delete { return 0 }
sub populate { return 1 }

package FakePort;
sub port { return $_[0]{port} }

package FakeSchema;
sub txn_do { my ($self, $code, @args) = @_; return $code->(@args) }
sub resultset { return App::Netdisco::DB->resultset($_[1]) }

package main;

my %device_cols = (
  ip => '192.0.2.1', uptime => 900, description => 'desc', name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', snmp_class => 'SNMP::Info::Layer2',
  custom_fields => '{}', snmp_ver => 2,
);

my %base_snmp = (
  v_name  => { 10 => 'Users', 20 => 'Servers' },
  v_index => { 10 => 10, 20 => 20 },
  interfaces => { 1 => 'Gi1/1', 2 => 'Gi1/2' },
  i_vlan => { 1 => 10, 2 => 10 },
  i_vlan_type => { 1 => 'static', 2 => 'static' },
  i_vlan_membership => { 1 => [10, 30], 2 => [10] },
  i_vlan_membership_untagged => { 1 => [10], 2 => [10] },
);

sub outcome {
  my ($method) = @_;
  return { method => $method, leaf => "MIB::$method", reason => 'timeout',
           rows => 1, walk => 'bulkwalk', complete => 0 };
}

my (@upserts, @removals, @warnings, @portvlan_writes);
our $stored_rows = [];
our $earlier_interfaces;

sub run_vlans {
  my (%snmp) = @_;
  delete @{ vars() }{qw/device_changed new_device device_ports hook_data timestamp incomplete_walks/};
  @upserts = @removals = @warnings = @portvlan_writes = ();
  vars->{'incomplete_walks'}{'192.0.2.1'}{'interfaces'} = [ $earlier_interfaces ]
    if $earlier_interfaces;

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_discover'} = 0;

  my $fake_snmp = FakeSNMP->new(%base_snmp, %snmp);
  no warnings 'once';

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::VLANs::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::VLANs::warning
    = sub { push @warnings, @_ };
  local *App::Netdisco::DB::Result::Device::ports
    = sub { return FakeRows->new(map { bless { port => $_ }, 'FakePort' } 'Gi1/1', 'Gi1/2') };
  local *App::Netdisco::DB::Result::Device::vlans
    = sub { return FakeRows->new(@$stored_rows) };
  local *FakeRows::populate = sub { push @portvlan_writes, $_[1]; return 1 };
  local *App::Netdisco::DB::Result::Device::port_vlans
    = sub { return FakeRows->new };
  local *App::Netdisco::DB::Upsert::upsert = sub {
    my ($rs, $rows, $options) = @_;
    push @upserts, [ $rs->result_source->source_name, $rows, $options ];
    return 0;
  };
  local *App::Netdisco::DB::Upsert::remove_unseen = sub {
    my ($rs, $scope, $seen) = @_;
    push @removals, [ $rs->result_source->source_name, $scope, $seen ];
    return 0;
  };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'discover::vlans',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

sub status_messages { return join "\n", map { $_->log } @{ $_[0]->_statuslist } }

sub vlan_upserts { return grep { $_->[0] eq 'DeviceVlan' } @upserts }
sub vlan_removals { return grep { $_->[0] eq 'DeviceVlan' } @removals }

subtest 'device_vlan__complete_walks__upserts_named_and_unnamed_and_removes_unseen' => sub {
  my $job = run_vlans();
  my @calls = vlan_upserts();
  is scalar @calls, 1, 'one upsert';
  my @rows = @{ $calls[0][1] };
  is_deeply [ map { $_->{vlan} } @rows ], [ 10, 20, 30 ], 'named in order, then unnamed';
  is_deeply [ sort keys %{ $rows[0] } ], [ qw/description ip last_discover vlan/ ],
    'creation is left out';
  is $rows[0]{ip}, '192.0.2.1';
  is $rows[0]{description}, 'Users';
  is $rows[2]{description}, 'VLAN 30';
  is ${ $rows[0]{last_discover} }, 'LOCALTIMESTAMP';
  is_deeply $calls[0][2], { touch => ['last_discover'] };
  my @removed = vlan_removals();
  is scalar @removed, 1, 'one removal';
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is_deeply $removed[0][2], [ { vlan => 10 }, { vlan => 20 }, { vlan => 30 } ];
  is_deeply [ map { $_->{vlan} } @{ vars->{'hook_data'}{'vlans'} } ], [ 10, 20, 30 ];
  is scalar @warnings, 0, 'no warning';
  like status_messages($job), qr/discovered for ports and device/;
};

subtest 'device_vlan__two_names_for_one_vlan__one_row_same_name_every_run' => sub {
  my @names;
  for (1 .. 5) {
    run_vlans(
      v_name  => { z => 'Zed', y => 'Why', x => 'Ex', 20 => 'Servers' },
      v_index => { z => 10, y => 10, x => 10, 20 => 20 },
    );
    my ($call) = vlan_upserts();
    my @ten = grep { $_->{vlan} == 10 } @{ $call->[1] };
    is scalar @ten, 1, 'one row for the VLAN';
    push @names, $ten[0]{description};
  }
  is_deeply [ keys %{{ map { $_ => 1 } @names }} ], ['Ex'], 'first sorted entry wins every run';
};

subtest 'device_vlan__incomplete_membership_walk__skips_device_vlan_keeps_port_vlans_as_today' => sub {
  my $job = run_vlans(fail_on_read => { i_vlan_membership => outcome('i_vlan_membership') });
  is scalar(vlan_upserts()), 0, 'no upsert';
  is scalar(vlan_removals()), 0, 'no removal';
  is scalar @portvlan_writes, 1, 'port VLANs are still written';
  ok scalar @{ $portvlan_writes[0] }, 'with rows';
  like status_messages($job),
    qr/\[192\.0\.2\.1\] device_vlan - kept existing rows, incomplete SNMP walk: i_vlan_membership /;
  is scalar @warnings, 1, 'one warning';
  like $warnings[0], qr/device_vlan - kept existing rows, incomplete SNMP walk: i_vlan_membership /;
  ok !$job->is_cancelled, 'the guard skips and never cancels';
};

subtest 'device_vlan__incomplete_interfaces_walk_earlier__skips' => sub {
  local $earlier_interfaces = outcome('interfaces');
  my $job = run_vlans();
  is scalar(vlan_upserts()), 0, 'no upsert';
  is scalar(vlan_removals()), 0, 'no removal';
  like status_messages($job), qr/device_vlan - kept existing rows, incomplete SNMP walk: interfaces /;
  is scalar @warnings, 1, 'one warning';
};

subtest 'device_vlan__setting_off_with_incomplete_walk__writes_what_came_back' => sub {
  local config->{'enable_incomplete_walk_protection'} = 0;
  my $job = run_vlans(fail_on_read => { i_vlan_membership => outcome('i_vlan_membership') });
  is scalar(vlan_upserts()), 1, 'upsert';
  is scalar(vlan_removals()), 1, 'removal';
  is scalar @warnings, 0, 'no warning';
};

subtest 'device_vlan__skip__hook_data_vlans_from_stored_rows' => sub {
  local $stored_rows = [ { vlan => 5, description => 'Old' } ];
  run_vlans(fail_on_read => { v_name => outcome('v_name') });
  is_deeply vars->{'hook_data'}{'vlans'}, $stored_rows;
};

done_testing;
