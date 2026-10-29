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
use App::Netdisco::Worker::Plugin::Discover::PortPower ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The PortPower worker runs for real with SNMP stubbed. upsert and remove_unseen
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
  peth_power_watts  => { 2 => 370, 1 => 740 },
  peth_power_status => { 1 => 'on', 2 => 'off' },
  interfaces => { 1 => 'Gi1/1', 2 => 'Gi1/2' },
  peth_port_ifindex => { '1.1' => 1, '1.2' => 2 },
  peth_port_admin   => { '1.1' => 'true', '1.2' => 'true' },
  peth_port_status  => { '1.1' => 'delivering', '1.2' => 'searching' },
  peth_port_class   => { '1.1' => 'class3', '1.2' => 'class0' },
  peth_port_power   => { '1.1' => 6000, '1.2' => 0 },
);

sub outcome {
  my ($method) = @_;
  return { method => $method, leaf => "MIB::$method", reason => 'timeout',
           rows => 1, walk => 'bulkwalk', complete => 0 };
}

my (@upserts, @removals, @warnings, @module_reads);

sub run_power {
  my (%snmp) = @_;
  delete @{ vars() }{qw/device_changed new_device device_ports hook_data timestamp incomplete_walks/};
  @upserts = @removals = @warnings = @module_reads = ();

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{_column_data}{since_last_discover} = 0;

  my $fake_snmp = FakeSNMP->new(%base_snmp, %snmp);
  no warnings 'once';

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::PortPower::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::PortPower::warning
    = sub { push @warnings, @_ };
  local *App::Netdisco::DB::Result::Device::ports
    = sub { return FakeRows->new(map { bless { port => $_ }, 'FakePort' } 'Gi1/1', 'Gi1/2') };
  local *App::Netdisco::DB::Result::Device::power_modules
    = sub { push @module_reads, 1; return FakeRows->new };
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
    job => 0, device => $device, action => 'discover::portpower',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

sub status_messages { return join "\n", map { $_->log } @{ $_[0]->_statuslist } }
sub error_messages { return map { $_->log } grep { $_->status eq 'error' } @{ $_[0]->_statuslist } }

sub power_upserts { return grep { $_->[0] eq 'DevicePower' } @upserts }
sub power_removals { return grep { $_->[0] eq 'DevicePower' } @removals }
sub port_upserts { return grep { $_->[0] eq 'DevicePortPower' } @upserts }
sub port_removals { return grep { $_->[0] eq 'DevicePortPower' } @removals }

subtest 'device_power__complete_walk__upserts_and_removes_unseen' => sub {
  my $job = run_power();
  my @calls = power_upserts();
  is scalar @calls, 1, 'one upsert';
  is_deeply $calls[0][1], [
    { ip => '192.0.2.1', module => 1, power => 740, status => 'on' },
    { ip => '192.0.2.1', module => 2, power => 370, status => 'off' },
  ], 'rows in module order, no timestamp columns';
  my @removed = power_removals();
  is scalar @removed, 1, 'one removal';
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is_deeply $removed[0][2], [ { module => 1 }, { module => 2 } ];
  is scalar @module_reads, 0, 'no delete and populate of device_power';
  is scalar(port_upserts()), 1, 'port power upserted';
  is scalar @warnings, 0, 'no warning';
  like status_messages($job), qr/added 2 new PoE capable ports/;
};

subtest 'port_power__normal_run__upserts_and_removes_unseen' => sub {
  run_power();
  my @calls = port_upserts();
  is scalar @calls, 1, 'one upsert';
  is_deeply $calls[0][1], [
    { ip => '192.0.2.1', port => 'Gi1/1', module => 1, admin => 'true',
      status => 'delivering', class => 'class3', power => 6000 },
    { ip => '192.0.2.1', port => 'Gi1/2', module => 1, admin => 'true',
      status => 'searching', class => 'class0', power => 0 },
  ], 'uniform rows, no timestamp columns';
  ok !defined $calls[0][2], 'no options';
  my @removed = port_removals();
  is scalar @removed, 1, 'one removal';
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is_deeply $removed[0][2], [ { port => 'Gi1/1' }, { port => 'Gi1/2' } ];
};

subtest 'port_power__duplicate_port_entries__first_entry_wins' => sub {
  run_power(peth_port_ifindex => { '1.1' => 1, '2.1' => 1 });
  my @calls = port_upserts();
  is scalar @{ $calls[0][1] }, 1, 'one row for the port';
  is $calls[0][1][0]{module}, 1;
};

subtest 'port_power__poe_gone_complete_walk__removes_port_power_rows' => sub {
  my $job = run_power(peth_power_watts => undef);
  is scalar(port_upserts()), 0, 'no upsert';
  my @removed = port_removals();
  is scalar @removed, 1, 'one removal';
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is_deeply $removed[0][2], [], 'every row goes';
  is scalar @warnings, 0, 'no warning';
};

subtest 'port_power__poe_gone_incomplete_port_walk__keeps_rows' => sub {
  my $job = run_power(peth_power_watts => undef,
    walk_status => { peth_port_power => outcome('peth_port_power') });
  is scalar(port_removals()), 0, 'no removal';
  is scalar(power_removals()), 1, 'device_power still emptied';
  like status_messages($job), qr/device_port_power - kept existing rows, incomplete SNMP walk: peth_port_power /;
};

for my $method (qw/interfaces peth_port_ifindex peth_port_admin peth_port_status peth_port_class peth_port_power/) {
  subtest "port_power__incomplete_${method}__keeps_rows" => sub {
    my $job = run_power(fail_on_read => { $method => outcome($method) });
    is scalar(port_upserts()), 0, 'no port upsert';
    is scalar(port_removals()), 0, 'no port removal';
    is scalar(power_upserts()), 1, 'device_power still written';
    is scalar @warnings, 1, 'one warning';
    like $warnings[0], qr/device_port_power - kept existing rows, incomplete SNMP walk: \Q$method\E /;
    ok !$job->is_cancelled, 'the guard skips and never cancels';
  };
}

subtest 'port_power__absent_port_walk__keeps_rows_and_errors_the_job' => sub {
  my $job = run_power(walk_status => { peth_port_class =>
    { %{ outcome('peth_port_class') }, reason => 'absent', complete => 1, rows => 0 } });
  is scalar(port_upserts()), 0, 'no port upsert';
  is scalar(port_removals()), 0, 'no port removal';
  my @errors = error_messages($job);
  is scalar @errors, 1, 'one error status';
  like $errors[0], qr/device_port_power .+ netdisco-mibs/;
};

subtest 'device_power__complete_walk_no_poe__removes_all_rows' => sub {
  my $job = run_power(peth_power_watts => undef);
  is scalar(power_upserts()), 0, 'no upsert';
  my @removed = power_removals();
  is scalar @removed, 1, 'one removal';
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is_deeply $removed[0][2], [], 'nothing seen, so every row goes';
  like status_messages($job), qr/\[192\.0\.2\.1\] power - 0 power modules/;
  is scalar(port_upserts()), 0, 'no port upsert';
  is scalar @warnings, 0, 'no warning';
};

subtest 'device_power__complete_walk_empty_hash__removes_rows_and_port_power_runs' => sub {
  my $job = run_power(peth_power_watts => {});
  is scalar(power_upserts()), 0, 'no upsert';
  my @removed = power_removals();
  is scalar @removed, 1, 'one removal';
  is_deeply $removed[0][2], [], 'every row goes';
  is scalar(port_upserts()), 1, 'port power upserted';
  like status_messages($job), qr/added 2 new PoE capable ports/;
  is scalar @warnings, 0, 'no warning';
};

subtest 'device_power__incomplete_walk_undef__keeps_rows' => sub {
  my $job = run_power(peth_power_watts => undef,
    fail_on_read => { peth_power_watts => outcome('peth_power_watts') });
  is scalar(power_upserts()), 0, 'no upsert';
  is scalar(power_removals()), 0, 'no removal';
  like status_messages($job),
    qr/\[192\.0\.2\.1\] device_power - kept existing rows, incomplete SNMP walk: peth_power_watts /;
  is scalar @warnings, 1, 'one warning';
  like $warnings[0], qr/device_power - kept existing rows, incomplete SNMP walk: peth_power_watts /;
  is scalar(port_upserts()), 0, 'no port upsert';
  is scalar(port_removals()), 0, 'port rows kept';
  ok !$job->is_cancelled, 'the guard skips and never cancels';
};

subtest 'device_power__absent_peth_power_watts__keeps_rows' => sub {
  my $job = run_power(peth_power_watts => undef, walk_status => { peth_power_watts =>
    { method => 'peth_power_watts', leaf => 'MIB::peth_power_watts', reason => 'absent',
      rows => 0, walk => 'bulkwalk', complete => 1 } });
  is scalar(power_upserts()), 0, 'no upsert';
  is scalar(power_removals()), 0, 'no removal';
  is scalar @warnings, 1, 'one warning';
  like status_messages($job), qr/device_power - kept existing rows, incomplete SNMP walk: peth_power_watts /;
};

subtest 'device_power__incomplete_walk__port_power_still_written' => sub {
  my $job = run_power(fail_on_read => { peth_power_status => outcome('peth_power_status') });
  is scalar(power_upserts()), 0, 'no upsert';
  is scalar(power_removals()), 0, 'no removal';
  is scalar @module_reads, 0, 'device_power rows untouched';
  my @calls = port_upserts();
  is scalar @calls, 1, 'port power still upserted';
  is scalar @{ $calls[0][1] }, 2, 'with both ports';
  my $status = status_messages($job);
  like $status, qr/added 2 new PoE capable ports/;
  like $status, qr/device_power - kept existing rows, incomplete SNMP walk: peth_power_status /;
  is scalar @warnings, 1, 'one warning';
};

subtest 'device_power__setting_off_with_incomplete_walk__writes_what_came_back' => sub {
  local config->{'enable_incomplete_walk_protection'} = 0;
  run_power(fail_on_read => { peth_power_watts => outcome('peth_power_watts') });
  is scalar(power_upserts()), 1, 'upsert';
  is scalar(power_removals()), 1, 'removal';
  is scalar(port_removals()), 1, 'port removal';
  is scalar @warnings, 0, 'no warning';
};

subtest 'device_power__untranslatable_watts_walk__skips_and_errors_the_job' => sub {
  my $job = run_power(peth_power_watts => undef, walk_status => {
    peth_power_watts => { %{ outcome('peth_power_watts') }, reason => 'absent', complete => 1, rows => 0 } });
  is scalar(power_upserts()), 0, 'no upsert';
  my @errors = error_messages($job);
  is scalar @errors, 1, 'one error status';
  like $errors[0], qr/device_power - kept existing rows, incomplete SNMP walk: peth_power_watts .+ netdisco-mibs/;
};

subtest 'device_power__untranslatable_status_walk__port_power_runs_and_errors_the_job' => sub {
  my $job = run_power(walk_status => {
    peth_power_status => { %{ outcome('peth_power_status') }, reason => 'absent', complete => 1, rows => 0 } });
  is scalar(power_upserts()), 0, 'no upsert';
  is scalar(port_upserts()), 1, 'port power still upserted';
  my @errors = error_messages($job);
  is scalar @errors, 1, 'one error status';
  like $errors[0], qr/added 2 new PoE capable ports; .+ peth_power_status .+ netdisco-mibs/;
};

subtest 'device_power__cut_short_walk__job_status_as_today' => sub {
  my $job = run_power(fail_on_read => { peth_power_status => outcome('peth_power_status') });
  is scalar(error_messages($job)), 0, 'no error status';
};

done_testing;
