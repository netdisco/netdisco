#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Backend::Job;
use App::Netdisco::Transport::SSH ();
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Worker::Plugin::Arpnip::Subnets ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The CLI arpnip subnets worker with store_vrfs on, run through the Runner as
# xt/194 runs the SNMP one. session_for is faked to return a session over a
# stub platform, and the Subnet resultset records the upsert_subnet calls.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

package FlatPlatform;
sub new { my ($class, %args) = @_; return bless { calls => [], %args }, $class }
sub subnets {
  my $self = shift;
  push @{ $self->{calls} }, [ 'subnets', @_ ];
  return @{ $self->{flat} || [] };
}

package ReportingPlatform;
our @ISA = ('FlatPlatform');
sub subnets_by_vrf {
  my $self = shift;
  push @{ $self->{calls} }, [ 'subnets_by_vrf', @_ ];
  die $self->{die} if $self->{die};
  return $self->{by_vrf};
}

# the SNMP side, as xt/194 fakes it: each context answers only for its VRF
package FakeSNMP;
our $AUTOLOAD;
sub new { my ($class, %vals) = @_; return bless { walk_failures => [], context => '', %vals }, $class }
sub walk_failures { $_[0]{walk_failures} }
sub walk_status { undef }
sub snmp_ver { 2 }
sub snmp_comm { 'public' }
sub update {
  my ($self, %args) = @_;
  $self->{context} = exists $args{Context} ? $args{Context}
    : ($args{Community} =~ m/\@(.+)$/ ? $1 : '');
  return 1;
}
sub _context_of {
  my ($self, $name) = @_;
  my $ctx = $self->{instances}{$name}{contexts}[0];
  return '' if not $ctx or ($ctx->{kind} || '') eq 'none';
  return $ctx->{id};
}
sub vrf_instances { $_[0]{context} eq '' ? $_[0]{instances} : undef }
sub vrf_instances_complete { $_[0]{context} eq '' ? 1 : undef }
sub _vrf_answer {
  my ($self, $what, $name) = @_;
  return undef unless $self->{context} eq $self->_context_of($name);
  return $self->{vrf}{$name}{$what};
}
sub vrf_subnets { $_[0]->_vrf_answer('subnets', $_[1]) }
sub vrf_read_complete { $_[0]->_vrf_answer('complete', $_[1]) }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  return $self->{$method};
}

package FakeSubnetRs;
sub new { bless {}, shift }
sub upsert_subnet { my $self = shift; push @main::upserts, [ @_ ]; return 1 }
sub resultset { return $_[0] }

package main;

my %device_cols = (
  ip => '192.0.2.1', name => 'router1', layers => '00000100', snmp_ver => 2,
  snmp_class => 'SNMP::Info::Layer3',
);

our @upserts;

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

sub by_vrf {
  return {
    default => [ { prefix => '172.20.20.0', len => 24 } ],
    red  => [ { prefix => '10.100.1.0', len => 24 }, { prefix => '2001:db8:1::', len => 64 } ],
    blue => [ { prefix => '10.100.1.0', len => 24 } ],
    @_,
  };
}

sub run_subnets {
  my (%args) = @_;
  delete @{ vars() }{qw/timestamp hook_data/};
  @upserts = ();

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_arpnip'} = 0;

  my $session = $args{platform}
    ? MySession->new(platform => $args{platform}, host => $device->ip, ssh => 'SSH', auth => { platform => 'Stub' })
    : undef;

  local *App::Netdisco::Transport::SSH::session_for = sub { return $session };
  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $args{snmp} };
  local *App::Netdisco::Worker::Plugin::Arpnip::Subnets::schema = sub { return FakeSubnetRs->new };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'arpnip::subnets',
  });

  with_settings(sub {
    try { MyWorker->new()->run($job) }
    catch { $job->status('error'); $job->log("error running job: $_") };
  }, device_auth => ($args{snmp} ? [{ driver => 'snmp' }, { driver => 'cli' }] : [{ driver => 'cli' }]), store_vrfs => 1, ignore_private_nets => 0, %{ $args{settings} || {} });

  return $job;
}

# net|vrf, ignoring the timestamp and the router
sub stored { return join ' ', sort map { join '|', $_->[0], $_->[2] // '-' } @upserts }
# the router each upsert names, deduplicated
sub routers { my %seen; return join ' ', sort grep { not $seen{$_}++ } map { $_->[3] // '-' } @upserts }
sub calls_of { my ($platform, $name) = @_; return grep { $_->[0] eq $name } @{ $platform->{calls} } }

subtest 'cli_subnets__switch_on_platform_by_vrf__stored_under_each_vrf' => sub {
  my $platform = ReportingPlatform->new(flat => ['192.0.2.0/24'], by_vrf => by_vrf());
  my $job = run_subnets(platform => $platform);
  is $job->status, 'info', 'arpnip finished with the store phase\'s info status';
  is scalar(calls_of($platform, 'subnets')), 0, 'flat subnets not called';
  my ($call) = calls_of($platform, 'subnets_by_vrf');
  is_deeply $call, [ 'subnets_by_vrf', '192.0.2.1', 'SSH', { platform => 'Stub' } ],
    'subnets_by_vrf called with the subnets arguments';
  is stored(), join(' ', sort '172.20.20.0/24|', '10.100.1.0/24|red', '10.100.1.0/24|blue', '2001:db8:1:0:0:0:0:0/64|red'),
    'default stored as the empty vrf; the same prefix in red and blue kept as two rows';
  is routers(), '192.0.2.1', 'every row names the device as its router';
};

subtest 'cli_subnets__default_and_empty_both_named__one_row' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(red => [], blue => [], '' => [ { prefix => '172.20.20.0', len => 24 } ]));
  run_subnets(platform => $platform);
  is scalar(@upserts), 1, 'one row for the prefix, not one per name';
  is stored(), '172.20.20.0/24|', 'stored under the empty vrf';
};

subtest 'cli_subnets__nxos_shaped_result_default_vrf__stored_as_the_empty_vrf' => sub {
  my $platform = ReportingPlatform->new(by_vrf => {
    default => [ { prefix => '192.0.2.0', len => 25 }, { prefix => '192.0.2.77', len => undef } ],
    management => [ { prefix => '172.20.20.0', len => 24 } ],
    'egress-loadbalance-resolution-' => [ { prefix => '10.0.0.0', len => 8 } ],
  });
  run_subnets(platform => $platform, settings => { ignore_private_nets => 1 });
  is stored(), '192.0.2.0/25|', 'default is the empty vrf, never a vrf literally named default';

  run_subnets(platform => $platform);
  is stored(), join(' ', sort '192.0.2.0/25|', '172.20.20.0/24|management', '10.0.0.0/8|egress-loadbalance-resolution-'),
    'every named VRF stored; the prefix with no length dropped';
};

subtest 'cli_subnets__host_and_link_local_routes__dropped' => sub {
  my $platform = ReportingPlatform->new(by_vrf => { red => [
    { prefix => '10.120.0.1', len => 32 },
    { prefix => '2001:db8:120::1', len => 128 },
    { prefix => 'fe80::', len => 64 },
    { prefix => '10.0.0.0', len => 0 },
    { prefix => '127.0.0.0', len => 8 },
    { prefix => '10.5.0.0' },
    { prefix => '10.6.0.0', len => 24 },
  ] });
  run_subnets(platform => $platform);
  is stored(), '10.6.0.0/24|red', 'only the connected network is stored';

  run_subnets(platform => $platform, settings => { ignore_private_nets => 1 });
  is stored(), '', 'ignore_private_nets drops RFC 1918';
};

subtest 'cli_subnets__skipped_vrf__not_stored' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf());
  run_subnets(platform => $platform, settings => { vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:blue' } });
  is stored(), join(' ', sort '172.20.20.0/24|', '10.100.1.0/24|red', '2001:db8:1:0:0:0:0:0/64|red'), 'blue not stored';
  run_subnets(platform => $platform, settings => { vrf_no_devicevrfs => { '192.0.2.1' => 'vrf:red' } });
  is stored(), join(' ', sort '172.20.20.0/24|', '10.100.1.0/24|blue'), 'vrf_no_devicevrfs drops red';
};

subtest 'cli_subnets__switch_off__flat_subnets_unchanged_no_by_vrf_call' => sub {
  my $platform = ReportingPlatform->new(flat => ['192.0.2.0/24', '198.51.100.0/24'], by_vrf => by_vrf());
  my $job = run_subnets(platform => $platform, settings => { store_vrfs => 0 });
  is $job->status, 'info', 'arpnip finished with the store phase\'s info status';
  is scalar(calls_of($platform, 'subnets_by_vrf')), 0, 'subnets_by_vrf not called';
  is stored(), '192.0.2.0/24| 198.51.100.0/24|', 'flat subnets stored under the empty vrf';
  is routers(), '192.0.2.1', 'flat rows name the device as their router';
};

subtest 'cli_subnets__platform_without_by_vrf__flat_as_today' => sub {
  my $platform = FlatPlatform->new(flat => ['192.0.2.0/24']);
  my $job = run_subnets(platform => $platform);
  is $job->status, 'info', 'arpnip finished with the store phase\'s info status';
  is scalar(calls_of($platform, 'subnets')), 1, 'flat subnets called';
  is stored(), '192.0.2.0/24|', 'stored under the empty vrf';
};

subtest 'cli_subnets__by_vrf_undef__nothing_stored_not_deferred' => sub {
  my $platform = ReportingPlatform->new(flat => ['192.0.2.0/24'], by_vrf => undef);
  my $job = run_subnets(platform => $platform);
  is $job->status, 'info', 'not deferred';
  is scalar(@upserts), 0, 'nothing stored, and no fall back to the flat list';
  is scalar(calls_of($platform, 'subnets')), 0, 'flat subnets not called';
};

subtest 'cli_subnets__malformed_vrf_value_or_entry__skipped_rest_stored' => sub {
  my $platform = ReportingPlatform->new(by_vrf => {
    red => 'x', blue => { 'a' => 1 },
    green => [ '10.0.0.0/8', [], { prefix => '10.7.0.0', len => 24 } ],
    '' => [ { prefix => '172.20.20.0', len => 24 } ],
  });
  my $job = run_subnets(platform => $platform);
  is $job->status, 'info', 'the job does not error';
  is stored(), '10.7.0.0/24|green 172.20.20.0/24|', 'well-formed entries stored, malformed skipped';
};

subtest 'cli_subnets__by_vrf_dies__nothing_stored_not_deferred' => sub {
  my $platform = ReportingPlatform->new(die => "boom\n");
  my $job = run_subnets(platform => $platform);
  is $job->status, 'info', 'not deferred';
  is scalar(@upserts), 0, 'nothing stored';
};

sub snmp_instance {
  my $name = shift;
  return { name => $name, kind => ($name eq 'default' ? 'default' : 'vrf'),
    contexts => ($name eq 'default' ? [{ kind => 'none' }]
      : [{ kind => 'vrf', id => $name, v2c => "%s\@$name", v3 => $name }]) };
}

sub snmp_subnet { my ($prefix, $len) = @_;
  return ("$prefix/$len" => { prefix => $prefix, len => $len,
    family => ($prefix =~ m/:/ ? 'ipv6' : 'ipv4'), ifindex => 1, sources => ['ipAddress'] }) }

subtest 'arpnip_subnets__snmp_and_cli_in_one_job__both_sources_stored_once_with_router' => sub {
  my $snmp = FakeSNMP->new(class => 'SNMP::Info::Layer3',
    instances => { default => snmp_instance('default'), red => snmp_instance('red'), green => snmp_instance('green') },
    vrf => {
      default => { complete => 1, subnets => { snmp_subnet('198.51.100.0', 24) } },
      red     => { complete => 1, subnets => { snmp_subnet('10.100.1.0', 24), snmp_subnet('203.0.113.0', 24) } },
      green   => { complete => 1, subnets => { snmp_subnet('10.200.0.0', 16) } },
    });
  my $platform = ReportingPlatform->new(by_vrf => by_vrf());
  my $job = run_subnets(platform => $platform, snmp => $snmp);
  is $job->status, 'info', 'arpnip finished with the store phase\'s info status';
  is scalar(calls_of($platform, 'subnets_by_vrf')), 1, 'the CLI worker ran in the same job as the SNMP one';
  is stored(), join(' ', sort '172.20.20.0/24|', '198.51.100.0/24|', '10.100.1.0/24|red', '203.0.113.0/24|red',
      '2001:db8:1:0:0:0:0:0/64|red', '10.100.1.0/24|blue', '10.200.0.0/16|green'),
    'the union of both sources under their VRFs; red 10.100.1.0/24, found by both, stored once';
  is routers(), '192.0.2.1', 'every row names the device as its router';
};

subtest 'store_cli_vrf_subnets__default_and_empty_both_named__counts_one_row' => sub {
  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  my $prefix = [ { prefix => '172.20.20.0', len => 24 } ];
  my $session = MySession->new(platform => ReportingPlatform->new(by_vrf => { default => $prefix, '' => $prefix }),
    host => $device->ip, ssh => 'SSH', auth => {});
  my ($status) = with_settings(sub {
    App::Netdisco::Worker::Plugin::Arpnip::Subnets::store_cli_vrf_subnets($device, $session) },
    store_vrfs => 1, ignore_private_nets => 0);
  like $status->log, qr/processed 1 Subnet entries/, 'one stored row, one counted';
};

subtest 'store_cli_vrf_subnets__stored_prefixes__info_status_with_count' => sub {
  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  my $session = MySession->new(platform => ReportingPlatform->new(by_vrf => by_vrf(
    blue => [ { prefix => '10.6.0.1', len => 32 } ])),
    host => $device->ip, ssh => 'SSH', auth => {});
  my ($status) = with_settings(sub {
    App::Netdisco::Worker::Plugin::Arpnip::Subnets::store_cli_vrf_subnets($device, $session) },
    store_vrfs => 1, ignore_private_nets => 0);
  is $status->status, 'info', 'status info';
  like $status->log, qr/processed 3 Subnet entries/, 'host route not counted';
};

done_testing;
