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
use App::Netdisco::Worker::Plugin::Discover::Properties ();
use App::Netdisco::Worker::Plugin::Discover::Properties::Tags ();

use JSON::PP ();
use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The Properties early workers run for real, as in xt/167-discover-device-ip-upsert.t,
# with SNMP and storage stubbed. The port writes are recorded, and the stored
# ports the job reads back are whatever the last recorded upsert wrote.

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
# the port tags worker runs inside discover::properties; its clear writes nothing here
{ package NoopTagsSchema; sub resultset { return $_[0] } sub search { return $_[0] } sub update { return 0 } }

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
sub reset { return $_[0] }
sub all { return @{ $_[0]->{rows}} }

package FakeLockedRow;
sub new { return bless {}, shift }
sub first { return $_[0] }

package FakeSchema;
sub txn_do { my ($self, $code) = @_; return $code->() }
sub resultset { my ($self, $name) = @_; return App::Netdisco::DB->resultset($name) }

package main;

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
  interfaces => { 1 => 'Gi0/1', 2 => 'Gi0/2' },
  i_type => { 1 => '6', 2 => '6' }, i_ignore => {},
  i_description => { 1 => 'Gi0/1', 2 => 'Gi0/2' },
  i_speed => { 1 => '1000000000', 2 => '1000000000' },
  i_lastchange => { 1 => 0, 2 => 0 },
  agg_ports => {}, i_subinterfaces => {},
);

sub outcome {
  my ($method) = @_;
  return { method => $method, leaf => "MIB::$method", reason => 'timeout',
           rows => 1, walk => 'bulkwalk', complete => 0 };
}

sub stored_port { my ($port, %cols) = @_; return { ip => '192.0.2.1', port => $port, %cols } }

my (@sequence, @upserts, @retired, @locks, @port_searches, $device_updates);
our $stored = [];

sub run_discover {
  my (%snmp) = @_;
  delete @{ vars() }{qw/device_changed new_device device_ports hook_data timestamp incomplete_walks/};
  @sequence = @upserts = @retired = @locks = @port_searches = ();
  $device_updates = 0;

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_discover'} = 0;

  my $fake_snmp = FakeSNMP->new(%base_snmp, %snmp);
  my $search = DBIx::Class::ResultSet->can('search');
  no warnings 'once';

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::Tags::schema
    = sub { return bless {}, 'NoopTagsSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::warning = sub { };
  local *App::Netdisco::DB::Result::Device::ports = sub {
    my ($self, $cond, $attrs) = @_;
    push @port_searches, $attrs;
    return FakeRows->new(map { {%$_} } @$stored)
      if ($attrs->{result_class} || '') =~ m/HashRefInflator/;
    return FakeRows->new(map { App::Netdisco::DB->resultset('DevicePort')->new_result({ %$_ }) } @$stored);
  };
  local *App::Netdisco::DB::Result::Device::device_ips = sub { return FakeRows->new };
  local *App::Netdisco::DB::Result::Device::update = sub { $device_updates++; return $_[0] };
  local *App::Netdisco::DB::Result::Device::update_or_insert = sub { return $_[0] };
  local *App::Netdisco::DB::ResultSet::Device::search = sub {
    my ($rs, $cond, $attrs) = @_;
    return $search->(@_) unless $attrs and $attrs->{for};
    push @sequence, 'lock';
    push @locks, [ $cond, $attrs ];
    return FakeLockedRow->new;
  };
  local *App::Netdisco::DB::ResultSet::DevicePort::txn_do_locked = sub {
    push @sequence, 'txn_do_locked';
    return $_[-1]->();
  };
  local *App::Netdisco::DB::Upsert::upsert = sub {
    my ($rs, $rows) = @_;
    my $source = $rs->result_source->source_name;
    push @sequence, "upsert $source";
    push @upserts, [ $source, $rows ];
    $stored = [ map { my %row = %$_; delete $row{creation}; \%row } @$rows ]
      if $source eq 'DevicePort';
    return 0;
  };
  local *App::Netdisco::DB::Upsert::remove_unseen = sub { return 0 };
  local *App::Netdisco::DB::ResultSet::DevicePort::retire_ports = sub {
    my ($rs, @args) = @_;
    push @sequence, 'retire_ports';
    push @retired, [ @args ];
    return scalar @{ $args[1] };
  };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'discover::properties',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

sub port_upserts { return grep { $_->[0] eq 'DevicePort' } @upserts }
sub statuses { return @{ $_[0]->_statuslist } }

subtest 'ports_write__normal_run__upserts_uniform_rows_with_ip_and_creation' => sub {
  local $stored = [];
  my $job = run_discover(i_subinterfaces => { 1 => [2] });
  is $job->status, 'done', 'job completes';
  my @calls = port_upserts();
  is scalar @calls, 1, 'one upsert';
  my @rows = @{ $calls[0][1] || [] };
  is_deeply [ sort map { $_->{port} } @rows ], [ 'Gi0/1', 'Gi0/2' ];
  my $keys = join ',', sort keys %{ $rows[0] };
  is scalar(grep { join(',', sort keys %$_) ne $keys } @rows), 0, 'every row has the same keys';
  foreach my $row (@rows) {
    is $row->{ip}, '192.0.2.1', "$row->{port} carries ip";
    is ${ $row->{creation} }, 'LOCALTIMESTAMP', "$row->{port} carries creation";
    ok !exists $row->{$_}, "$row->{port} has no $_"
      for qw/custom_fields tags remote_ip is_uplink manual_topo first_seen/;
  }
  my %by_port = map {($_->{port} => $_)} @rows;
  is $by_port{'Gi0/1'}{has_subinterfaces}, 1, 'a port with subinterfaces';
  is $by_port{'Gi0/2'}{has_subinterfaces}, 0, 'a port with no subinterfaces';
  is $by_port{'Gi0/2'}{is_master}, 0, 'not an aggregate master';
  is $by_port{'Gi0/2'}{slave_of}, 'Gi0/1', 'subinterface parent kept';
};

subtest 'ports_write__port_gone__retires_it_vanished' => sub {
  local $stored = [ stored_port('Gi0/1'), stored_port('Gi0/9') ];
  run_discover(interfaces => { 1 => 'Gi0/1' });
  is_deeply \@retired, [ [ '192.0.2.1', [ 'Gi0/9' ], 'vanished' ] ];
};

subtest 'ports_write__early_ignored_stored_port__retires_it_vanished' => sub {
  local $stored = [ stored_port('Gi0/1'), stored_port('Gi0/9') ];
  local config->{'ignore_deviceports'} = [ { '192.0.2.1' => 'port:Gi0/9' } ];
  run_discover(interfaces => { 1 => 'Gi0/1', 9 => 'Gi0/9' });
  my @calls = port_upserts();
  is_deeply [ map { $_->{port} } @{ $calls[0][1] || [] } ], [ 'Gi0/1' ], 'the ignored port is not written';
  is_deeply \@retired, [ [ '192.0.2.1', [ 'Gi0/9' ], 'vanished' ] ];
};

subtest 'ports_write__no_table_lock__locks_the_device_row' => sub {
  local $stored = [];
  run_discover();
  is scalar(grep { $_ eq 'txn_do_locked' } @sequence), 0, 'no table lock';
  is scalar @locks, 1, 'one row lock';
  is_deeply $locks[0][0], { ip => '192.0.2.1' }, 'on the device row';
  is $locks[0][1]{for}, 'update', 'FOR UPDATE';
  my @order = grep { $_ eq 'lock' or $_ eq 'upsert DevicePort' } @sequence;
  is_deeply \@order, [ 'lock', 'upsert DevicePort' ], 'lock taken before the upsert';
};

subtest 'ports_write__incomplete_interfaces__skips_and_reads_hook_ports_from_db' => sub {
  local $stored = [ stored_port('Gi0/1', descr => 'old', has_subinterfaces => 0, is_master => 0),
                    stored_port('Gi0/9', has_subinterfaces => 0, is_master => 0) ];
  my $job = run_discover(interfaces => { 1 => 'Gi0/1' },
    fail_on_read => { interfaces => outcome('interfaces') });
  is scalar(port_upserts()), 0, 'no upsert';
  is scalar @retired, 0, 'no retire_ports';
  is_deeply vars->{'hook_data'}{'ports'},
    [ map { { %$_, has_subinterfaces => 'false', is_master => 'false', custom_fields => '{}' } } @$stored ],
    'hook ports are the stored rows';
  my ($read) = grep { ($_->{result_class} || '') =~ m/HashRefInflator/ } @port_searches;
  is $read->{order_by}, 'port', 'stored order';
  is_deeply $read->{columns}, [qw/port descr up up_admin mac speed speed_admin mtu name
    duplex duplex_admin stp type vlan pvid has_subinterfaces is_master slave_of lastchange
    custom_fields/], 'the columns the hook diff and payload read';
  ok !vars->{'device_changed'}, 'ports count as unchanged';
  ok $device_updates, 'the device row is still updated';
  my ($skip) = grep { $_->log =~ m/device_port - kept existing rows/ } statuses($job);
  ok $skip, 'skip status';
  is +($skip ? $skip->status : undef), 'info', 'at info level';
  like +($skip ? $skip->log : ''), qr/\[192\.0\.2\.1\] device_port - kept existing rows, incomplete SNMP walk: interfaces/;
  ok !$job->is_cancelled, 'the guard skips and never cancels';
};

# Tags port ACLs (prop:val and cf:field:value) read the payload, so a skip must
# give it the walk path's shape
subtest 'ports_write__skip__payload_booleans_as_strings' => sub {
  local $stored = [ stored_port('Gi0/1', has_subinterfaces => 1, is_master => 0),
                    stored_port('Gi0/2', has_subinterfaces => undef, is_master => 't') ];
  run_discover(fail_on_read => { i_speed => outcome('i_speed') });
  my %by_port = map {($_->{port} => $_)} @{ vars->{'hook_data'}{'ports'} };
  is $by_port{'Gi0/1'}{has_subinterfaces}, 'true';
  is $by_port{'Gi0/1'}{is_master}, 'false';
  is $by_port{'Gi0/2'}{has_subinterfaces}, 'false';
  is $by_port{'Gi0/2'}{is_master}, 'true';
};

my $stored_fields = '{"site":"lab","retired_field":"x"}';
my $configured_fields = JSON::PP->new->encode({ site => 'lab' });

subtest 'ports_write__normal_run__payload_carries_configured_custom_fields' => sub {
  local $stored = [ stored_port('Gi0/1', custom_fields => $stored_fields) ];
  local config->{'custom_fields'} = { device_port => [ { name => 'site' } ] };
  run_discover();
  my %by_port = map {($_->{port} => $_)} @{ vars->{'hook_data'}{'ports'} };
  is $by_port{'Gi0/1'}{custom_fields}, $configured_fields, 'stored port: configured fields only';
  ok !exists $by_port{'Gi0/2'}{custom_fields}, 'new port: none, as before';
  my @calls = port_upserts();
  is scalar(grep { exists $_->{custom_fields} } @{ $calls[0][1] || [] }), 0,
    'the upsert rows never carry custom_fields';
};

subtest 'ports_write__skip__payload_carries_configured_custom_fields' => sub {
  local $stored = [ stored_port('Gi0/1', custom_fields => $stored_fields) ];
  local config->{'custom_fields'} = { device_port => [ { name => 'site' } ] };
  run_discover(fail_on_read => { i_speed => outcome('i_speed') });
  is vars->{'hook_data'}{'ports'}[0]{custom_fields}, $configured_fields;
};

subtest 'ports_write__incomplete_i_speed__skips' => sub {
  local $stored = [ stored_port('Gi0/1') ];
  my $job = run_discover(fail_on_read => { i_speed => outcome('i_speed') });
  is scalar(port_upserts()), 0, 'no upsert';
  is scalar @retired, 0, 'no retire_ports';
  ok scalar(grep { $_->log =~ m/device_port - kept existing rows, incomplete SNMP walk: i_speed/ }
    statuses($job)), 'skip names the walk';
};

subtest 'ports_write__new_port__is_in_the_cache_after_the_write' => sub {
  local $stored = [ stored_port('Gi0/1') ];
  run_discover();
  is_deeply [ sort keys %{ vars->{'device_ports'} } ], [ 'Gi0/1', 'Gi0/2' ];
  is vars->{'device_ports'}{'Gi0/2'}->port, 'Gi0/2', 'cached as a port row';
  is $port_searches[-1]{prefetch}, 'properties', 'same query as the first fill';
};

subtest 'ports_write__protection_off__writes_what_came_back' => sub {
  local $stored = [ stored_port('Gi0/1'), stored_port('Gi0/9') ];
  local config->{'enable_incomplete_walk_protection'} = 0;
  run_discover(interfaces => { 1 => 'Gi0/1' },
    fail_on_read => { interfaces => outcome('interfaces') });
  my @calls = port_upserts();
  is scalar @calls, 1, 'one upsert';
  is_deeply [ map { $_->{port} } @{ $calls[0][1] || [] } ], [ 'Gi0/1' ];
  is_deeply \@retired, [ [ '192.0.2.1', [ 'Gi0/9' ], 'vanished' ] ];
};

done_testing;
