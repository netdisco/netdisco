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

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The alias worker runs for real, as in xt/51-updated-device-hook.t, with SNMP
# and storage stubbed. upsert and remove_unseen are replaced by recorders, so
# no database is needed.

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
config->{'ignore_private_nets'} = 0;
config->{'dns'}->{'no'} = ['0.0.0.0/0'];

package FakeSNMP;
our $AUTOLOAD;
sub new { my ($class, %vals) = @_; return bless { walk_failures => [], %vals }, $class; }
sub walk_failures { $_[0]{walk_failures} }
sub walk_status { $_[0]{walk_status}{$_[1]} }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  $self->{reads}{$method}++;
  # a failing walk records itself on its first read only, as a cached table does
  if (my $failure = delete $self->{fail_on_read}{$method}) {
    push @{ $self->{walk_failures} }, $failure;
    $self->{walk_status}{$method} = $failure;
  }
  # a failure kept in walk_failures only, so walk_status stays clear
  push @{ $self->{walk_failures} }, delete $self->{fail_log_only}{$method}
    if $self->{fail_log_only}{$method};
  return $self->{$method};
}

package FakeRows;
sub new { my ($class, @rows) = @_; return bless { rows => [@rows] }, $class; }
sub reset { return $_[0] }
sub all { return @{ $_[0]->{rows}} }
sub delete { return 0 }
sub populate { return 1 }

package FakeDevicePortRS;
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
  ip_index   => { '192.0.2.1' => 1, '198.51.100.7' => 2 },
  ip_table   => { '192.0.2.1' => '192.0.2.1', '198.51.100.7' => '198.51.100.7' },
  ip_netmask => { '192.0.2.1' => '255.255.255.0', '198.51.100.7' => '255.255.255.0' },
);

sub outcome {
  my ($method) = @_;
  return { method => $method, leaf => "MIB::$method", reason => 'timeout',
           rows => 1, walk => 'bulkwalk', complete => 0 };
}

my (@upserts, @removals, @warnings, @device_ip_searches);
our $stored_rows = [];
my $last_snmp;

sub run_discover {
  my (%snmp) = @_;
  delete @{ vars() }{qw/device_changed new_device device_ports hook_data timestamp incomplete_walks/};
  @upserts = @removals = @warnings = @device_ip_searches = ();

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_discover'} = 0;

  my $fake_snmp = FakeSNMP->new(%base_snmp, %snmp);
  $last_snmp = $fake_snmp;
  no warnings 'once';

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::DB::Result::Device::ports = sub { return FakeRows->new };
  local *App::Netdisco::DB::Result::Device::device_ips
    = sub { push @device_ip_searches, [@_[1 .. $#_]]; return FakeRows->new(@$stored_rows) };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::warning
    = sub { push @warnings, @_ };
  local *App::Netdisco::DB::Result::Device::update = sub { return $_[0] };
  local *App::Netdisco::DB::Result::Device::update_or_insert = sub { return $_[0] };
  local *App::Netdisco::DB::Upsert::upsert = sub {
    my ($rs, $rows) = @_;
    push @upserts, [ $rs->result_source->source_name, $rows ];
    return 0;
  };
  local *App::Netdisco::DB::Upsert::remove_unseen = sub {
    my ($rs, $scope, $seen) = @_;
    push @removals, [ $rs->result_source->source_name, $scope, $seen ];
    return 0;
  };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'discover::properties',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

# finalise_status keeps only the best status in $job->log, and a later worker's
# done() replaces this worker's info(), so read every status the workers returned
sub status_messages { return join "\n", map { $_->log } @{ $_[0]->_statuslist } }

sub device_ip_upserts { return grep { $_->[0] eq 'DeviceIp' } @upserts }
sub device_ip_removals { return grep { $_->[0] eq 'DeviceIp' } @removals }

subtest 'device_ip__complete_walks__upserts_rows_and_removes_unseen_with_ip_scope' => sub {
  run_discover();
  my @calls = device_ip_upserts();
  is scalar @calls, 1, 'one upsert';
  my @rows = @{ $calls[0][1] };
  is_deeply [ map { $_->{alias} } @rows ], [ '192.0.2.1', '198.51.100.7' ];
  is_deeply [ sort keys %{ $rows[0] } ], [qw/alias creation dns ip port subnet vrf/],
    'rows carry the same keys and leave out first_seen';
  is $rows[0]{ip}, '192.0.2.1';
  is $rows[0]{port}, 'Gi1/1';
  is $rows[0]{subnet}, '192.0.2.0/24';
  is ${ $rows[0]{creation} }, 'LOCALTIMESTAMP';
  my @removed = device_ip_removals();
  is scalar @removed, 1, 'one removal';
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is_deeply $removed[0][2], [ { alias => '192.0.2.1', vrf => '' }, { alias => '198.51.100.7', vrf => '' } ];
};

subtest 'device_ip__second_identical_run__same_rows_in_same_order' => sub {
  my %ipv6 = (
    ipv6_index => { 'a' => 1, 'b' => 2, 'c' => 1 },
    ipv6_addr  => { a => '2001:db8::5', b => '2001:db8::1', c => '2001:DB8:0:0:0:0:0:5' },
    ipv6_type  => { a => 'unicast', b => 'unicast', c => 'unicast' },
    ipv6_addr_prefixlength => { a => 64, b => 64, c => 48 },
  );
  my (@first, @second);
  for my $pass (1, 2) {
    run_discover(%ipv6);
    my @calls = device_ip_upserts();
    my $rows = [ map { { %$_, creation => 'now' } } @{ $calls[0][1] } ];
    if ($pass == 1) { @first = @$rows } else { @second = @$rows }
  }
  is_deeply \@second, \@first;
  my ($five) = grep { $_->{alias} eq '2001:db8:0:0:0:0:0:5' } @first;
  is $five->{port}, 'Gi1/1', 'first sorted entry wins the duplicate';
  is $five->{subnet}, '2001:db8:0:0:0:0:0:0/64';
};

subtest 'device_ip__ipv6_alias_in_two_spellings__one_row' => sub {
  run_discover(
    ipv6_index => { a => 1, b => 2 },
    ipv6_addr  => { a => '2001:db8::5', b => '2001:0DB8:0:0:0:0:0:5' },
    ipv6_type  => { a => 'unicast', b => 'unicast' },
  );
  my @calls = device_ip_upserts();
  is scalar(grep { $_->{alias} =~ /^2001/ } @{ $calls[0][1] }), 1;
};

subtest 'device_ip__device_ip_not_in_ip_index__fake_row_added_once' => sub {
  run_discover(
    ip_index => { '198.51.100.7' => 2 },
    ip_table => { '198.51.100.7' => '198.51.100.7' },
    ip_netmask => {},
  );
  my @calls = device_ip_upserts();
  is_deeply [ map { $_->{alias} } @{ $calls[0][1] } ], [ '198.51.100.7', '192.0.2.1' ];
  my ($fake) = grep { $_->{alias} eq '192.0.2.1' } @{ $calls[0][1] };
  ok !defined $fake->{port} && !defined $fake->{subnet}, 'fake row has no port or subnet';
  is_deeply [ sort keys %$fake ], [qw/alias creation dns ip port subnet vrf/];

  run_discover(ip_index => {}, ip_table => {}, ip_netmask => {});
  @calls = device_ip_upserts();
  is_deeply [ map { $_->{alias} } @{ $calls[0][1] } ], [ '192.0.2.1' ],
    'no ip_index at all still lists the device once';
};

subtest 'device_ip__incomplete_ip_index__skips_and_logs_table_and_walk' => sub {
  my $job = run_discover(fail_on_read => { ip_index => outcome('ip_index') });
  is scalar(device_ip_upserts()), 0, 'no upsert';
  is scalar(device_ip_removals()), 0, 'no removal';
  is scalar(grep { $_->[0] eq 'Subnet' } @upserts), 0, 'subnets untouched';
  like status_messages($job),
    qr/\[192\.0\.2\.1\] device_ip - kept existing rows, incomplete SNMP walk: ip_index/;
  ok !$job->is_cancelled, 'the guard skips and never cancels';
  is scalar @warnings, 1, 'one warning';
  like $warnings[0], qr/\[192\.0\.2\.1\] device_ip - kept existing rows, incomplete SNMP walk: ip_index/;
};

subtest 'device_ip__incomplete_interfaces_walk_earlier__skips' => sub {
  my $job = run_discover(fail_on_read => { interfaces => outcome('interfaces') });
  is scalar(device_ip_upserts()), 0, 'no upsert';
  is scalar(device_ip_removals()), 0, 'no removal';
  like status_messages($job), qr/device_ip - kept existing rows, incomplete SNMP walk: interfaces/;
};

subtest 'device_ip__interfaces_failure_only_in_job_record__skips' => sub {
  run_discover(fail_log_only => { interfaces => outcome('interfaces') });
  is scalar(device_ip_upserts()), 0, 'no upsert';
  is scalar(device_ip_removals()), 0, 'no removal';
};

subtest 'device_ip__skip__hook_data_device_ips_from_stored_rows' => sub {
  local $stored_rows = [ { ip => '192.0.2.1', alias => '203.0.113.9', dns => 'old.example' } ];
  run_discover(fail_on_read => { ip_index => outcome('ip_index') });
  is_deeply vars->{'hook_data'}{'device_ips'}, $stored_rows;
  my $attrs = $device_ip_searches[0][1];
  is_deeply $attrs->{columns}, [qw/alias subnet port dns/], 'stored columns';
  is $attrs->{order_by}, 'alias', 'stored order';
  is $attrs->{result_class}, 'DBIx::Class::ResultClass::HashRefInflator', 'plain hashes';
};

# vrf_name index 3.114.101.100 is the length-prefixed context name "red"
my %vrf_snmp = (
  cisco_comm_indexing => 1, snmp_comm => 'public', vtp_version => 2,
  vrf_name => { '3.114.101.100' => 'red' },
);

sub in_context { my ($method, $context) = @_; return { %{ outcome($method) }, context => $context } }

subtest 'device_ip__incomplete_walk_in_vrf_context__upserts_rows' => sub {
  run_discover(%vrf_snmp, fail_log_only => { ip_index => in_context('ip_index', 'red') });
  is scalar(device_ip_upserts()), 1, 'one upsert';
  is scalar(device_ip_removals()), 1, 'one removal';
  is scalar @warnings, 0, 'no warning';
};

subtest 'device_ip__incomplete_vrf_name_walk__upserts_rows' => sub {
  run_discover(%vrf_snmp, vrf_name => {},
    fail_on_read => { vrf_name => outcome('vrf_name') });
  is scalar(device_ip_upserts()), 1, 'one upsert';
};

subtest 'device_ip__incomplete_base_walk_with_vrfs__skips' => sub {
  run_discover(%vrf_snmp, fail_log_only => { ip_index => in_context('ip_index', '') });
  is scalar(device_ip_upserts()), 0, 'no upsert';
  is scalar(device_ip_removals()), 0, 'no removal';
};

subtest 'device_ip__incomplete_walk_in_context_not_a_vrf__skips' => sub {
  run_discover(%vrf_snmp, fail_log_only => { ip_index => in_context('ip_index', 'mgmt') });
  is scalar(device_ip_upserts()), 0, 'no upsert';
};

sub absent_in { my ($method, $context) = @_;
  return { %{ in_context($method, $context) }, reason => 'absent', complete => 1, rows => 0 } }

# walk_status holds the last VRF's outcome, so a broken MIB shows in a VRF context
subtest 'device_ip__absent_walk_on_vrf_device__skips' => sub {
  run_discover(%vrf_snmp, walk_status => { ip_index => absent_in('ip_index', 'red') });
  is scalar(device_ip_upserts()), 0, 'no upsert';
};

subtest 'device_ip__absent_vrf_name_walk__skips' => sub {
  run_discover(%vrf_snmp, vrf_name => {}, walk_status => { vrf_name => absent_in('vrf_name', '') });
  is scalar(device_ip_upserts()), 0, 'no upsert';
};

# index 3.114.101.1 decodes to no context, so that VRF is walked in the base context
subtest 'device_ip__vrf_with_no_context__base_walk_failure_still_skips' => sub {
  run_discover(%vrf_snmp, vrf_name => { '3.114.101.1' => 'odd' },
    fail_log_only => { ip_index => in_context('ip_index', '') });
  is scalar(device_ip_upserts()), 0, 'no upsert';
};

subtest 'device_ip__vrf_device__vrf_list_read_once' => sub {
  run_discover(%vrf_snmp);
  is $last_snmp->{reads}{vrf_name}, 1, 'one vrf_name read';
};

sub error_messages { return map { $_->log } grep { $_->status eq 'error' } @{ $_[0]->_statuslist } }

subtest 'device_ip__untranslatable_walk__skips_and_errors_the_job' => sub {
  my $job = run_discover(walk_status => {
    ip_table => { %{ outcome('ip_table') }, reason => 'absent', complete => 1, rows => 0 } });
  is scalar(device_ip_upserts()), 0, 'no upsert';
  my @errors = error_messages($job);
  is scalar @errors, 1, 'one error status';
  like $errors[0], qr/device_ip - kept existing rows, incomplete SNMP walk: ip_table .+ netdisco-mibs/;
};

subtest 'device_ip__absent_walk_on_vrf_device__errors_the_job' => sub {
  my $job = run_discover(%vrf_snmp, walk_status => { ip_index => absent_in('ip_index', 'red') });
  is scalar(error_messages($job)), 1, 'one error status';
};

subtest 'device_ip__cut_short_walk__job_status_as_today' => sub {
  my $job = run_discover(fail_on_read => { ip_index => outcome('ip_index') });
  is scalar(error_messages($job)), 0, 'no error status';
};

done_testing;
