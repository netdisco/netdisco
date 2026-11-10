#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

# After a complete arpnip, a router retires the active entries it was the last
# to report and did not report this run (spec 4.6): in VRFs it read whole, in
# VRFs it no longer lists when its list was whole, and in skipped VRFs. With
# collection off for the device only named VRF rows go, so a site that never
# turns store_vrfs on sees no change; with it on but no VRF reads (an SSH or
# offline job, a class without VRF support) nothing goes. Only the database
# handle is faked; these check the SQL and binds sent, then the store
# worker's call through the Runner.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Backend::Job;
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Worker::Plugin::Arpnip::Nodes ();
use App::Netdisco::Util::Node 'retire_unvouched_arps';

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

config->{'device_auth'} = [{driver => 'snmp'}];
config->{'dns'}->{'no'} = ['0.0.0.0/0'];

my (@ran, $txns, @stored_vrfs);

package FakeDbh;
sub new { return bless {}, $_[0] }
sub do  { my ($self, $sql, undef, @binds) = @_; push @ran, [$sql, @binds]; return 3 }
sub selectcol_arrayref {
  my ($self, $sql, undef, @binds) = @_;
  push @ran, [$sql, @binds];
  # as PostgreSQL would apply the named-only predicate
  return [ grep { $sql !~ m/vrf <> ''/ or $_ ne '' } @stored_vrfs ];
}

package FakeSchema;
sub new     { return bless { dbh => FakeDbh->new }, $_[0] }
sub txn_do  { ++$txns; return $_[1]->() }
sub storage { return $_[0] }
sub dbh_do  { my ($self, $code) = @_; return $code->($self, $self->{dbh}) }

package main;

{ no warnings 'redefine'; *App::Netdisco::Util::Node::schema = sub { FakeSchema->new }; }

my $router = '198.51.100.1';

# the unit tests below run with collection on unless they say otherwise
set store_vrfs => 1;
my $now = 'to_timestamp(1.5)::timestamp';

sub device {
  my $device = App::Netdisco::DB->resultset('Device')->new_result({
    ip => $router, name => 'router1', layers => '00000100', snmp_ver => 2,
    snmp_class => 'SNMP::Info::Layer3' });
  $device->in_storage(1);
  return $device;
}

sub with_settings {
  my ($code, %settings) = @_;
  my %saved = map { $_ => setting($_) } keys %settings;
  set($_ => $settings{$_}) for keys %settings;
  my @result = eval { $code->() };
  my $error = $@;
  set($_ => $saved{$_}) for keys %saved;
  die $error if $error;
  return @result;
}

# stored: the VRFs this router's active rows sit in
sub run_retire {
  my ($stored, @args) = @_;
  @ran = (); $txns = 0; @stored_vrfs = @$stored;
  my $count = retire_unvouched_arps(device(), @args);
  return ($count, @ran);
}

sub updates_of { return grep { $_->[0] =~ m/^\s*UPDATE node_ip/ } @_ }
sub update_of { return (updates_of(@_))[0] }

# the named VRFs' UPDATE binds its list; the default table's names it in the SQL
sub retired_vrfs {
  my @updates = updates_of(@_) or return undef;
  my @vrfs = map { ($_->[0] =~ m/ANY/ ? @{ $_->[-1] } : ($_->[0] =~ m/vrf = ''\s*$/ ? '' : ())) } @updates;
  return [ sort @vrfs ];
}

subtest 'retire__switch_on__complete_vrfs_and_uncovered_vrfs_retired' => sub {
  my ($count, @stmts) = run_retire(['', 'gone', 'red'], $now, { '' => 1, red => 1 }, 1);
  is_deeply retired_vrfs(@stmts), ['', 'gone', 'red'],
    'default and red read whole, gone no longer listed';
  is $count, 6, 'returns the rows deactivated by both UPDATEs';
};

subtest 'retire__switch_on__incomplete_vrf_excluded' => sub {
  my (undef, @stmts) = run_retire(['', 'red'], $now, { '' => 1, red => 0 }, 1);
  is_deeply retired_vrfs(@stmts), [''], 'red read short, so red kept';
  my (undef, @none) = run_retire(['', 'red'], $now, { '' => 0, red => 0 }, 1);
  ok !update_of(@none), 'no UPDATE when nothing qualifies, the default table included';
};

subtest 'retire__switch_on__short_vrf_list__uncovered_vrfs_kept' => sub {
  my (undef, @stmts) = run_retire(['', 'gone', 'red'], $now, { '' => 1, red => 1 }, 0);
  is_deeply retired_vrfs(@stmts), ['', 'red'], 'gone may only be missing from a short list';
  my (undef, @absent) = run_retire(['', 'gone'], $now, { '' => 1 });
  is_deeply retired_vrfs(@absent), [''], 'an absent list completeness reads as short';
};

subtest 'retire__switch_on__skipped_vrf__retired_even_with_short_list' => sub {
  my (undef, @by_name) = with_settings(sub {
    run_retire(['', 'blue', 'gone'], $now, { '' => 1 }, 0) }, vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:blue' });
  is_deeply retired_vrfs(@by_name), ['', 'blue'], 'vrf_no_devicevrfs for every device';
  my (undef, @by_device) = with_settings(sub {
    run_retire(['', 'blue', 'gone'], $now, { '' => 1 }, 0) }, vrf_no_devicevrfs => { $router => 'vrf:gone' });
  is_deeply retired_vrfs(@by_device), ['', 'gone'], 'vrf_no_devicevrfs';
};

sub check_named_only {
  my ($count, @stmts) = @_;
  is scalar @stmts, 2, 'lock and one UPDATE, no VRF query';
  my $update = update_of(@stmts);
  like $update->[0], qr/AND vrf <> ''\s*$/, 'never the default table';
  unlike $update->[0], qr/ANY/, 'no VRF list';
  is_deeply [@$update[1 .. $#$update]], [$router], 'router is the only bind';
  is $count, 3, 'returns the rows deactivated';
}

subtest 'retire__switch_off__named_vrfs_only' => sub {
  check_named_only(with_settings(sub { run_retire(['', 'red'], $now, undef, undef) }, store_vrfs => 0));
};

subtest 'retire__switch_on_device_in_skip_vrf_devices__named_vrfs_only' => sub {
  check_named_only(with_settings(sub { run_retire(['', 'red'], $now, undef, undef) },
    skip_vrf_devices => [$router]));
  my (undef, @stmts) = with_settings(sub { run_retire(['', 'red'], $now, { '' => 1 }, 1) },
    skip_vrf_devices => [$router]);
  like update_of(@stmts)->[0], qr/AND vrf <> ''\s*$/, 'a stale vrf_read does not override the device skip';
};

subtest 'retire__switch_on_offline_snapshot_device__named_vrfs_only' => sub {
  @ran = (); $txns = 0; @stored_vrfs = ('', 'red');
  my $device = device();
  $device->set_column(is_pseudo => \'true');
  my $count = retire_unvouched_arps($device, $now, undef, undef);
  check_named_only($count, @ran);
};

subtest 'retire__switch_on__named_statements_carry_the_partial_index_predicate' => sub {
  my (undef, $lock, $select, $named, $default) = run_retire(['', 'red'], $now, { '' => 1, red => 1 }, 1);
  like $select->[0], qr/AND vrf <> ''\s*$/, 'VRF query over named rows only';
  like $named->[0], qr/AND vrf <> '' AND vrf = ANY\(\?::text\[\]\)\s*$/, 'named UPDATE';
  is_deeply $named->[-1], ['red'], 'named list';
  like $default->[0], qr/AND vrf = ''\s*$/, 'the default table in its own UPDATE';
  is scalar(@{ $default }), 2, 'router is its only bind';
};

subtest 'retire__other_router_latest__not_matched' => sub {
  my (undef, $lock, $select, @updates) = run_retire(['', 'red'], $now, { '' => 1, red => 1 }, 1);
  like $select->[0], qr/WHERE active AND router_last = \? AND time_last < /, 'VRF query scoped to the router';
  is $select->[1], $router, 'VRF query binds this router';
  is scalar @updates, 2, 'named and default UPDATEs';
  for my $update (@updates) {
    like $update->[0], qr/WHERE active AND router_last = \? AND time_last < /, 'UPDATE scoped to the router';
    is $update->[1], $router, 'UPDATE binds this router';
  }
};

subtest 'retire__null_router_last__never_matched' => sub {
  for my $args ([$now, { '' => 1 }, 1], [$now, undef, undef]) {
    my (undef, @stmts) = with_settings(sub { run_retire([''], @$args) },
      store_vrfs => (defined $args->[1] ? 1 : 0));
    my $sql = update_of(@stmts)->[0];
    like $sql, qr/router_last = \?/, 'equality, which a NULL never satisfies';
    unlike $sql, qr/router_last IS NULL|COALESCE|router_last IS NOT DISTINCT/i, 'no NULL match';
    ok defined update_of(@stmts)->[1], 'router bind defined';
  }
};

subtest 'retire__offline_job_timestamp__inlined_as_given' => sub {
  my $entered = q{'2026-11-01 10:00:00'::timestamp};
  my (undef, undef, $select, $update) = run_retire([''], $entered, { '' => 1 }, 1);
  ok index($select->[0], "time_last < $entered") >= 0, 'VRF query';
  ok index($update->[0], "time_last < $entered") >= 0, 'UPDATE';
  my (undef, undef, $off) = with_settings(sub { run_retire([], $entered, undef, undef) }, store_vrfs => 0);
  ok index($off->[0], "time_last < $entered") >= 0, 'switch off UPDATE';
};

subtest 'retire__lock__taken_on_the_router_ip' => sub {
  for my $args ([$now, { '' => 1 }, 1], [$now, undef, undef]) {
    my (undef, @stmts) = with_settings(sub { run_retire([''], @$args) },
      store_vrfs => (defined $args->[1] ? 1 : 0));
    like $stmts[0][0], qr/SELECT pg_advisory_xact_lock\(\?, hashtext\(host\(\?::inet\)\)\)/, 'lock first';
    is_deeply [@{ $stmts[0] }[1 .. 2]], [1728, $router], 'ARP class, router IP';
    is $txns, 1, 'one transaction';
  }
};

# the store worker, run through the Runner with SNMP faked as xt/193 does

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

package FakeSNMP;
our $AUTOLOAD;
sub new { my ($class, %vals) = @_; return bless { %vals }, $class }
sub walk_failures { [] }
sub walk_status { undef }
sub vrf_neighbors { $_[0]{vrf_neighbors_by_name}{ $_[1] } }
sub vrf_read_complete { $_[0]{vrf_read_complete_by_name}{ $_[1] } }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  return $self->{$method};
}

package FakeCLI;
sub new { return bless {}, $_[0] }
# a session stands in for its own platform, which has no arpnip_by_vrf
sub platform { return $_[0] }
sub arpnip { return ({ ip => '192.0.2.10', mac => '00:11:22:33:44:01' }) }

package main;

my %base_snmp = (
  class => 'SNMP::Info::Layer3',
  at_paddr   => { '1.192.0.2.10' => '00:11:22:33:44:01' },
  at_netaddr => { '1.192.0.2.10' => '192.0.2.10' },
);

our @warnings;

sub run_arpnip {
  my (%args) = @_;
  delete @{ vars() }{qw/arps timestamp hook_data/};
  my @order;
  @warnings = ();
  my $device = device();
  $device->{'_column_data'}{'since_last_arpnip'} = 0;
  my $fake_snmp = FakeSNMP->new(%base_snmp, %{ $args{snmp} || {} });
  no warnings 'once';

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return ($args{unreachable} ? undef : $fake_snmp) };
  local *App::Netdisco::Transport::SSH::session_for = sub { return FakeCLI->new };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::store_arp = sub { push @order, ['store'] };
  # own-row lookup needs a database; xt/203 covers it
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::own_identity = sub { return ({}, {}, {}) };
  my $retire = \&App::Netdisco::Worker::Plugin::Arpnip::Nodes::retire_unvouched_arps;
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::retire_unvouched_arps = sub {
    push @order, ['retire', @_];
    die "deadlock detected\n" if $args{retire_dies};
    return ($args{real_retire} ? $retire->(@_) : 0) };
  local *App::Netdisco::DB::Result::Device::update = sub { push @order, ['update', $_[1]]; return $_[0] };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::warning = sub { push @warnings, @_ };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::hostnames_resolve_async = sub { push @order, ['resolve']; return $_[0] };

  my $job = App::Netdisco::Backend::Job->new({ job => 0, device => $device, action => 'arpnip::nodes' });
  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };
  return ($job, @order);
}

subtest 'retire__job_not_done__not_called' => sub {
  my ($job, @order) = with_settings(sub { run_arpnip(unreachable => 1) }, store_vrfs => 0);
  isnt $job->status, 'done', 'arpnip not done';
  is_deeply [ map { $_->[0] } @order ], ['resolve'], 'store phase ran, retire not called';
};

subtest 'retire__job_done__called_after_store_with_the_store_timestamp' => sub {
  my ($job, @order) = with_settings(sub { run_arpnip() }, store_vrfs => 0);
  is $job->status, 'done', 'arpnip done';
  is_deeply [ map { $_->[0] } @order ], ['resolve', 'store', 'retire', 'update'], 'after the store_arp loop';
  my (undef, $device, $ts, $vrf_read, $list_complete) = @{ $order[-2] };
  is $device->ip, $router, 'this router';
  is $ts, vars->{'timestamp'}, 'the timestamp store_arp was given';
  ok !defined $vrf_read, 'switch off passes no VRF reads';
  ok !defined $list_complete, 'switch off passes no list completeness';
};

subtest 'retire__fails__warns_and_job_done_with_last_arpnip_updated' => sub {
  my ($job, @order) = with_settings(sub { run_arpnip(retire_dies => 1) }, store_vrfs => 0);
  is $job->status, 'done', 'arpnip done';
  is_deeply [ map { $_->[0] } @order ], ['resolve', 'store', 'retire', 'update'], 'update still reached';
  is_deeply $order[-1][1], { last_arpnip => \vars->{'timestamp'} }, 'last_arpnip set to the store timestamp';
  is scalar(grep { m/retir.*failed.*deadlock detected/ } @warnings), 1, 'one warning naming the error';
};

# attribution mode, so no context switch: red is read in place, blue has no
# context that serves its rows
my %wired_snmp = (
  vrf_instances_complete => 1,
  vrf_instances => {
    default => { name => 'default', kind => 'default', contexts => [{ kind => 'none' }] },
    red     => { name => 'red', kind => 'vrf', contexts => [{ kind => 'none' }] },
    blue    => { name => 'blue', kind => 'vrf', contexts => [] },
  },
  vrf_neighbors_by_name => {
    default => { '1.192.0.2.10' => { ifindex => 1, ip => '192.0.2.10', mac => '00:11:22:33:44:01', family => 'ipv4' } },
    red     => { '7.10.40.0.5' => { ifindex => 7, ip => '10.40.0.5', mac => '00:11:22:33:44:07', family => 'ipv4' } },
  },
  # blue would report itself whole if asked, so only not entering it reads 0
  vrf_read_complete_by_name => { default => 1, red => 1, blue => 1 },
);

subtest 'retire__switch_on_vrf_reads__receives_vrf_read_and_list_completeness' => sub {
  my ($job, @order) = with_settings(sub { run_arpnip(snmp => \%wired_snmp) }, store_vrfs => 1);
  is $job->status, 'done', 'arpnip done';
  my ($call) = grep { $_->[0] eq 'retire' } @order;
  my (undef, $device, $ts, $vrf_read, $list_complete) = @$call;
  is $device->ip, $router, 'this router';
  is $ts, vars->{'timestamp'}, 'the timestamp store_arp was given';
  is_deeply $vrf_read, { '' => 1, red => 1, blue => 0 }, 'each VRF and whether it was read whole';
  is $list_complete, 1, 'the VRF list was whole';
  is scalar(grep { $_->[0] eq 'store' } @order), 2, 'default and red entries stored';
};

subtest 'retire__switch_on_cli_only_job__retires_nothing' => sub {
  @ran = (); @stored_vrfs = ('', 'red');
  my ($job, @order) = with_settings(sub { run_arpnip(real_retire => 1) },
    store_vrfs => 1, device_auth => [{driver => 'cli'}]);
  is $job->status, 'done', 'arpnip done';
  ok scalar(grep { $_->[0] eq 'retire' } @order), 'retire reached';
  ok !exists vars->{'vrf_read'}, 'the SSH collector reads no VRFs';
  is_deeply \@ran, [], 'no lock, no query, no UPDATE';
};

subtest 'retire__switch_on_unsupported_class__retires_nothing' => sub {
  @ran = (); @stored_vrfs = ('', 'red');
  my ($job, @order) = with_settings(sub { run_arpnip(real_retire => 1) }, store_vrfs => 1);
  is $job->status, 'done', 'arpnip done';
  ok scalar(grep { $_->[0] eq 'retire' } @order), 'retire reached';
  ok !exists vars->{'vrf_read'}, 'vrf_instances_complete undef, so no VRF reads';
  is_deeply \@ran, [], 'no lock, no query, no UPDATE';
};

subtest 'retire__switch_on_no_vrf_reads__unit__retires_nothing' => sub {
  my ($count, @stmts) = run_retire(['', 'red'], $now, undef, 1);
  is scalar @stmts, 0, 'no lock, no query, no UPDATE';
  is $count, 0, 'nothing retired';
};

subtest 'arpnip_timestamp_sql__microsecond_padding__orders_correctly' => sub {
  my $early = App::Netdisco::Worker::Plugin::Arpnip::Nodes::_arpnip_timestamp_sql(1000, 99999);
  my $later = App::Netdisco::Worker::Plugin::Arpnip::Nodes::_arpnip_timestamp_sql(1000, 100000);
  is $early, 'to_timestamp(1000.099999)::timestamp', '99999 us is 0.099999 s';
  is $later, 'to_timestamp(1000.100000)::timestamp', '100000 us is 0.1 s';
  my ($e) = $early =~ /\(([\d.]+)\)/; my ($l) = $later =~ /\(([\d.]+)\)/;
  cmp_ok $e, '<', $l, 'numeric order matches time order';
  like App::Netdisco::Worker::Plugin::Arpnip::Nodes::_arpnip_timestamp_sql(5, 5), qr/\(5\.000005\)/, '5 us padded';
};

done_testing;
