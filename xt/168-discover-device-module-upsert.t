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
use App::Netdisco::Worker::Plugin::Discover::Entities ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The Entities worker runs for real with SNMP stubbed. upsert and remove_unseen
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
config->{'store_modules'} = 1;

package FakeSNMP;
our $AUTOLOAD;
sub new { my ($class, %vals) = @_; return bless { walk_failures => [], %vals }, $class; }
sub walk_failures { $_[0]{walk_failures} }
sub walk_status { $_[0]{walk_status}{$_[1]} }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  $self->{read}{$method}++;
  # a failing walk records itself on its first read only, as a cached table does
  if (my $failure = delete $self->{fail_on_read}{$method}) {
    push @{ $self->{walk_failures} }, $failure;
    $self->{walk_status}{$method} = $failure;
  }
  return $self->{$method};
}

package FakeSchema;
sub txn_do { my ($self, $code, @args) = @_; return $code->(@args) }
sub resultset { return App::Netdisco::DB->resultset($_[1]) }

package main;

my %device_cols = (
  ip => '192.0.2.1', uptime => 900, description => 'desc', name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', chassis_id => 'chassis1', contact => '',
  location => 'Room A', num_ports => 2, snmp_class => 'SNMP::Info::Layer2',
  snmp_engineid => '', custom_fields => '{}', snmp_ver => 2,
);

my %entities = (
  e_index  => { a => 1, b => 2, c => 3 },
  e_descr  => { a => 'Chassis', b => 'Card', c => 'Port' },
  e_type   => { a => 't1', b => 't2', c => 't3' },
  e_parent => { a => 0, b => 1, c => 2 },
  e_name   => { a => ' Name A ', b => 'B', c => 'C' },
  e_class  => { a => 'chassis', b => 'module', c => 'port' },
  e_pos    => { a => -1, b => 1, c => 2 },
  e_hwver  => {}, e_fwver => {}, e_swver => {},
  e_model  => { a => 'M1' }, e_serial => { a => 'S1' },
  e_fru    => { a => 'false', b => 'true', c => 'false' },
);

sub outcome {
  my ($method) = @_;
  return { method => $method, leaf => "MIB::$method", reason => 'timeout',
           rows => 1, walk => 'bulkwalk', complete => 0 };
}

my (@upserts, @removals, @warnings);
my $last_snmp;

sub run_entities {
  my (%snmp) = @_;
  @upserts = @removals = @warnings = ();

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_discover'} = 0;

  my $fake_snmp = FakeSNMP->new(%entities, %snmp);
  $last_snmp = $fake_snmp;
  no warnings 'once';

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::Entities::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::Entities::warning
    = sub { push @warnings, @_ };
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
    job => 0, device => $device, action => 'discover::entities',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

sub status_messages { return join "\n", map { $_->log } @{ $_[0]->_statuslist } }
sub error_messages { return map { $_->log } grep { $_->status eq 'error' } @{ $_[0]->_statuslist } }

sub module_upserts { return grep { $_->[0] eq 'DeviceModule' } @upserts }
sub module_removals { return grep { $_->[0] eq 'DeviceModule' } @removals }

subtest 'device_module__complete_walk__upserts_with_touch_and_removes_unseen' => sub {
  run_entities();
  my @calls = module_upserts();
  is scalar @calls, 1, 'one upsert';
  my @rows = @{ $calls[0][1] };
  is_deeply [ map { $_->{index} } @rows ], [ 1, 2, 3 ];
  is_deeply [ sort keys %{ $rows[0] } ], [ sort qw/class description fw_ver hw_ver index ip last_discover
    model name parent pos serial sw_ver type fru/ ], 'creation is left out';
  is $rows[0]{ip}, '192.0.2.1';
  is $rows[0]{name}, 'Name A', 'name is trimmed';
  is ${ $rows[0]{last_discover} }, 'LOCALTIMESTAMP';
  is_deeply $calls[0][2], { touch => ['last_discover'] };
  my @removed = module_removals();
  is scalar @removed, 1, 'one removal';
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is_deeply $removed[0][2], [ { index => 1 }, { index => 2 }, { index => 3 } ];
  is_deeply [ @{ $last_snmp->{walk_failures} } ], [], 'sanity: nothing failed';
};

subtest 'device_module__invalid_parent__relocated_to_root' => sub {
  run_entities(e_parent => { a => 0, b => 1, c => 99 });
  my ($call) = module_upserts();
  my ($c) = grep { $_->{index} == 3 } @{ $call->[1] };
  ok !defined $c->{parent}, 'parent 99 does not exist so the entity is attached as root';
};

subtest 'device_module__duplicate_index__same_entry_kept_every_run' => sub {
  my %dup = (
    e_index => { z => 5, y => 5, x => 5 },
    e_name  => { z => 'Z', y => 'Y', x => 'X' },
    e_descr => {}, e_type => {}, e_parent => {}, e_class => {}, e_pos => {},
    e_model => {}, e_serial => {}, e_fru => {},
  );
  my @names;
  for (1 .. 5) {
    run_entities(%dup);
    my ($call) = module_upserts();
    is scalar @{ $call->[1] }, 1, 'one row for the index';
    push @names, $call->[1][0]{name};
  }
  is_deeply [ keys %{{ map { $_ => 1 } @names }} ], ['X'], 'first sorted entry wins every run';
};

subtest 'device_module__complete_walk_no_entities__chassis_row_and_removes_others' => sub {
  my $job = run_entities(e_index => undef);
  my @calls = module_upserts();
  is scalar @calls, 1, 'one upsert';
  my @rows = @{ $calls[0][1] };
  is scalar @rows, 1;
  is_deeply { %{ $rows[0] }, last_discover => ${ $rows[0]{last_discover} } }, {
    ip => '192.0.2.1', index => 1, parent => 0, name => 'chassis', class => 'chassis',
    pos => -1, sw_ver => '1.0', serial => 'SN1', model => 'cat', fru => 'false',
    type => undef, hw_ver => undef, fw_ver => undef, description => undef,
    last_discover => 'LOCALTIMESTAMP',
  };
  is_deeply $calls[0][2], { touch => ['last_discover'] };
  my @removed = module_removals();
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is_deeply $removed[0][2], [ { index => 1 } ];
  like status_messages($job), qr/0 chassis components/;
};

subtest 'device_module__incomplete_e_index_undef__skips_no_wipe' => sub {
  my $job = run_entities(e_index => undef, fail_on_read => { e_index => outcome('e_index') });
  is scalar(module_upserts()), 0, 'no upsert';
  is scalar(module_removals()), 0, 'no removal';
  like status_messages($job),
    qr/\[192\.0\.2\.1\] device_module - kept existing rows, incomplete SNMP walk: e_index/;
  is scalar @warnings, 1, 'one warning';
  like $warnings[0], qr/device_module - kept existing rows, incomplete SNMP walk: e_index/;
  ok !$job->is_cancelled, 'the guard skips and never cancels';
};

subtest 'device_module__incomplete_column_walk__skips' => sub {
  my $job = run_entities(fail_on_read => { e_serial => outcome('e_serial') });
  is scalar(module_upserts()), 0, 'no upsert';
  is scalar(module_removals()), 0, 'no removal';
  like status_messages($job), qr/device_module - kept existing rows, incomplete SNMP walk: e_serial/;
  is scalar @warnings, 1, 'one warning';
};

subtest 'device_module__e_index_cached_incomplete_from_earlier__skips' => sub {
  my $job = run_entities(walk_status => { e_index => outcome('e_index') });
  is scalar(module_upserts()), 0, 'no upsert';
  is scalar(module_removals()), 0, 'no removal';
  like status_messages($job), qr/device_module - kept existing rows, incomplete SNMP walk: e_index/;
  is scalar @warnings, 1, 'one warning';
};

subtest 'device_module__store_modules_off__chassis_row_without_snmp' => sub {
  local config->{'store_modules'} = 0;
  my $job = run_entities(fail_on_read => { e_index => outcome('e_index') });
  is_deeply $last_snmp->{read} || {}, {}, 'SNMP is not read';
  my @calls = module_upserts();
  is scalar @calls, 1, 'one upsert';
  is $calls[0][1][0]{name}, 'chassis';
  for my $column (qw/type hw_ver fw_ver description/) {
    ok exists $calls[0][1][0]{$column} && !defined $calls[0][1][0]{$column}, "$column cleared";
  }
  my @removed = module_removals();
  is_deeply $removed[0][2], [ { index => 1 } ];
  like status_messages($job), qr/store_modules is disabled/;
  is scalar @warnings, 0, 'no warning';
};

subtest 'device_module__untranslatable_walk__skips_and_errors_the_job' => sub {
  my $job = run_entities(walk_status => {
    e_index => { %{ outcome('e_index') }, reason => 'absent', complete => 1, rows => 0 } });
  is scalar(module_upserts()), 0, 'no upsert';
  my @errors = error_messages($job);
  is scalar @errors, 1, 'one error status';
  like $errors[0], qr/device_module - kept existing rows, incomplete SNMP walk: e_index .+ netdisco-mibs/;
};

subtest 'device_module__cut_short_walk__job_status_as_today' => sub {
  my $job = run_entities(fail_on_read => { e_serial => outcome('e_serial') });
  is scalar(error_messages($job)), 0, 'no error status';
};

done_testing;
