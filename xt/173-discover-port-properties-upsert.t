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
use App::Netdisco::DB::ResultSet::DevicePort ();
use App::Netdisco::Backend::Job;
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Worker::Plugin::Discover::PortProperties ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The PortProperties worker runs for real with SNMP stubbed. upsert,
# remove_unseen, retire_ports and the PAE update are replaced by recorders,
# so no database is needed.

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
  if (my $failure = delete $self->{fail_on_read}{$method}) {
    push @{ $self->{walk_failures} }, $failure;
    $self->{walk_status}{$method} = $failure;
  }
  # SNMP::Info returns an empty list, not undef, for a method the device does
  # not support, so a caller in list context sees no value at all
  return unless exists $self->{$method};
  return $self->{$method};
}

package FakePort;
sub port { return $_[0]{port} }
sub remote_ip { return undef }

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
  interfaces => { 1 => 'Gi0/1', 2 => 'Gi0/2' },
  i_speed_raw => { 1 => 1000000000, 2 => 100000000 },
  i_err_disable_cause => { 2 => 'bpduguard' },
  i_faststart_enabled => { 1 => 'true' },
);

sub outcome {
  my ($method) = @_;
  return { method => $method, leaf => "MIB::$method", reason => 'timeout',
           rows => 1, walk => 'bulkwalk', complete => 0 };
}

my (@upserts, @removals, @retired, @pae_calls, @warnings);
our $port_cache;

sub run_properties {
  my (%snmp) = @_;
  delete @{ vars() }{qw/device_changed new_device device_ports hook_data timestamp incomplete_walks/};
  @upserts = @removals = @retired = @pae_calls = @warnings = ();
  vars->{'device_ports'} = $port_cache
    = { map { ($_ => bless { port => $_ }, 'FakePort') } ("Gi0/1", "Gi0/2", "Gi0/5") };

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_discover'} = 0;

  my $fake_snmp = FakeSNMP->new(%base_snmp, %snmp);

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::PortProperties::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::PortProperties::warning
    = sub { push @warnings, @_ };
  local *App::Netdisco::Worker::Plugin::Discover::PortProperties::update_pae_attributes
    = sub { push @pae_calls, [ scalar @upserts, scalar @removals ]; return 1 };
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
  local *App::Netdisco::DB::ResultSet::DevicePort::retire_ports = sub {
    my ($rs, $ip, $ports, $mode) = @_;
    push @retired, [ $ip, $ports, $mode ];
    return scalar @$ports;
  };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'discover::portproperties',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

sub status_messages { return join "\n", map { $_->log } @{ $_[0]->_statuslist } }
sub property_upserts { return grep { $_->[0] eq 'DevicePortProperties' } @upserts }
sub property_removals { return grep { $_->[0] eq 'DevicePortProperties' } @removals }

subtest 'port_properties__normal_run__upserts_uniform_rows_and_removes_unseen' => sub {
  my $job = run_properties();
  my @calls = property_upserts();
  is scalar @calls, 1, 'one upsert';
  my @rows = @{ $calls[0][1] };
  is_deeply [ map { $_->{port} } @rows ], [ 'Gi0/1', 'Gi0/2' ], 'sorted by port';
  my @columns = sort keys %{ $rows[0] };
  is_deeply [ sort keys %{ $rows[1] } ], \@columns, 'rows are uniform';
  my @expected = sort (qw/ip port/, App::Netdisco::DB->source('DevicePortProperties')->columns);
  is_deeply \@columns, [ sort { $a cmp $b } keys %{{ map { $_ => 1 } @expected }} ],
    'every column of the table is present';
  ok((grep { m/^pae_/ } @columns) == 8, 'every pae_* column is present');
  is $rows[0]{ip}, '192.0.2.1';
  is $rows[0]{raw_speed}, 1000000000;
  is $rows[0]{faststart}, 'true';
  is $rows[1]{error_disable_cause}, 'bpduguard';
  is $rows[1]{faststart}, 'false', 'column default stands in for a missing value';
  is $rows[1]{remote_is_discoverable}, 'true';
  my @removed = property_removals();
  is scalar @removed, 1, 'one removal';
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is_deeply $removed[0][2], [ { port => 'Gi0/1' }, { port => 'Gi0/2' } ];
  is_deeply \@pae_calls, [ [ 1, 1 ] ], 'PAE update runs after the write';
  is scalar @warnings, 0, 'no warning';
  like status_messages($job), qr/added 2 new port properties/;
};

subtest 'port_properties__pae_disabled__pae_columns_written_null' => sub {
  run_properties();
  my ($call) = property_upserts();
  foreach my $row (@{ $call->[1] }) {
    foreach my $column (grep { m/^pae_/ } keys %$row) {
      ok !defined $row->{$column}, "$row->{port} $column is NULL";
    }
  }
};

subtest 'port_properties__no_properties_complete_walk__removes_all_rows' => sub {
  my $job = run_properties(
    interfaces => {}, i_speed_raw => {}, i_err_disable_cause => {}, i_faststart_enabled => {},
  );
  is scalar(property_upserts()), 0, 'nothing to upsert';
  my @removed = property_removals();
  is scalar @removed, 1, 'remove_unseen still runs';
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is_deeply $removed[0][2], [], 'with an empty seen list';
  is scalar @pae_calls, 1, 'PAE update still runs';
  ok !$job->is_cancelled;
};

foreach my $method (qw/interfaces i_speed_raw/) {
  subtest "port_properties__incomplete_${method}_walk__keeps_rows" => sub {
    my $job = run_properties(fail_on_read => { $method => outcome($method) });
    is scalar(property_upserts()), 0, 'no upsert';
    is scalar(property_removals()), 0, 'no removal';
    is scalar @pae_calls, 0, 'no PAE update';
    is scalar @warnings, 1, 'one warning';
    like $warnings[0],
      qr/\[192\.0\.2\.1\] port properties - kept existing rows, incomplete SNMP walk: \Q$method\E /;
    like status_messages($job), qr/kept existing rows/;
    ok !$job->is_cancelled, 'the guard skips and never cancels';
  };
}

subtest 'port_properties__ignored_port__retired_in_ignored_mode' => sub {
  local config->{'ignore_deviceports'} = [ { '192.0.2.1' => 'raw_speed:^100000000$' } ];
  run_properties();
  is_deeply \@retired, [ [ '192.0.2.1', ['Gi0/2'], 'ignored' ] ], 'one retire_ports call';
  my ($call) = property_upserts();
  is_deeply [ map { $_->{port} } @{ $call->[1] } ], ['Gi0/1'], 'no properties row for it';
  my ($removed) = property_removals();
  is_deeply $removed->[2], [ { port => 'Gi0/1' } ];
};

subtest 'port_properties__ignored_port__dropped_from_port_cache' => sub {
  local config->{'ignore_deviceports'} = [ { '192.0.2.1' => 'raw_speed:^100000000$' } ];
  run_properties();
  ok !exists vars->{'device_ports'}{'Gi0/2'}, 'ignored port is gone from the cache';
  ok exists vars->{'device_ports'}{'Gi0/1'}, 'other ports stay';
  ok exists vars->{'device_ports'}{'Gi0/5'}, 'ports without properties stay';
};

done_testing;
