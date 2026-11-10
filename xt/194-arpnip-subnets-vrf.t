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
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Worker::Plugin::Arpnip::Subnets ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The SNMP arpnip subnets worker run through the Runner as xt/193 runs the
# nodes worker. SNMP is faked and the Subnet resultset records the
# upsert_subnet calls it is given.

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

sub new {
  my ($class, %vals) = @_;
  return bless { walk_failures => [], context => '', contexts_asked => [], %vals }, $class;
}
sub walk_failures { $_[0]{walk_failures} }
sub walk_status { undef }
sub snmp_ver { $_[0]{snmp_ver} || 2 }
sub snmp_comm { 'public' }
sub update {
  my ($self, %args) = @_;
  $self->{context} = exists $args{Context} ? $args{Context}
    : ($args{Community} =~ m/\@(.+)$/ ? $1 : '');
  push @{ $self->{contexts_asked} }, $self->{context};
  return 1;
}

sub _context_of {
  my ($self, $name) = @_;
  my $ctx = $self->{instances}{$name}{contexts}[0];
  return '' if not $ctx or ($ctx->{kind} || '') eq 'none';
  return $ctx->{id};
}
sub vrf_instances {
  my $self = shift;
  $self->{reads}{vrf_instances}++;
  return $self->{context} eq '' ? $self->{instances} : undef;
}
sub vrf_instances_complete {
  my $self = shift;
  return $self->{context} eq '' ? $self->{instances_complete} : undef;
}
sub _vrf_answer {
  my ($self, $what, $name) = @_;
  push @{ $self->{vrf_reads}{$name} }, $what;
  return undef unless $self->{context} eq $self->_context_of($name);
  return $self->{vrf}{$name}{$what};
}
sub vrf_subnets { $_[0]->_vrf_answer('subnets', $_[1]) }
sub vrf_read_complete { $_[0]->_vrf_answer('complete', $_[1]) }

sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  $self->{reads}{$method}++;
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

# today's table: a public subnet, a private one, a /32, a loopback and 0.0.0.0
my %base_snmp = (
  class => 'SNMP::Info::Layer3',
  ip_netmask => {
    '198.51.100.1' => '255.255.255.0',
    '10.1.2.3'     => '255.255.255.0',
    '198.51.100.9' => '255.255.255.255',
    '127.0.0.1'    => '255.0.0.0',
    '0.0.0.0'      => '0.0.0.0',
  },
);

sub context_record { my $name = shift;
  return [{ kind => 'vrf', id => $name, v2c => "%s\@$name", v3 => $name }] }

sub instance {
  my ($name) = @_;
  return {
    name => $name, kind => ($name eq 'default' ? 'default' : 'vrf'),
    contexts => ($name eq 'default' ? [{ kind => 'none' }] : context_record($name)),
  };
}

sub subnet { my ($prefix, $len, $ifindex) = @_;
  return ("$prefix/$len" => { prefix => $prefix, len => $len,
    family => ($prefix =~ m/:/ ? 'ipv6' : 'ipv4'), ifindex => $ifindex, sources => ['ipAddress'] }) }

sub vrf_fixture {
  return (
    instances_complete => 1,
    instances => { default => instance('default'), red => instance('red') },
    vrf => {
      default => { complete => 1, subnets => { subnet('198.51.100.0', 24, 1) } },
      red     => { complete => 1, subnets => { subnet('203.0.113.0', 24, 7),
                                                subnet('2001:db8:40::', 64, 7) } },
    },
  );
}

our @upserts;
my $last_snmp;

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

sub run_subnets {
  my (%snmp) = @_;
  # subnets is left for the early worker to clear, as netdisco-do runs every
  # job in one process
  delete @{ vars() }{qw/timestamp hook_data/};
  @upserts = ();

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_arpnip'} = 0;

  my $fake_snmp = FakeSNMP->new(%base_snmp, %snmp);
  $last_snmp = $fake_snmp;

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Arpnip::Subnets::schema = sub { return FakeSubnetRs->new };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'arpnip::subnets',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

sub run_with_vrfs {
  my (%snmp) = @_;
  my $settings = delete $snmp{settings} || {};
  return with_settings(sub { run_subnets(vrf_fixture(), %snmp) }, store_vrfs => 1, %$settings);
}

# net|vrf|router, ignoring the timestamp argument
sub calls { return join ' ', sort map { join '|', $_->[0], $_->[2] // '-', $_->[3] // '-' } @upserts }

my $todays = do { with_settings(sub { run_subnets() }, store_vrfs => 0, ignore_private_nets => 0); calls() };

subtest 'arpnip_subnets__switch_off__today_calls' => sub {
  is $todays, '10.1.2.0/24||192.0.2.1 198.51.100.0/24||192.0.2.1',
    'ip_netmask path: loopback, 0.0.0.0 and /32 skipped, empty vrf and the device as router';
  with_settings(sub { run_subnets(vrf_fixture()) }, store_vrfs => 0, ignore_private_nets => 0);
  is calls(), $todays, 'VRF data ignored with the switch off';
  ok !$last_snmp->{reads}{vrf_instances}, 'vrf_instances not read';
  ok !$last_snmp->{vrf_reads}, 'vrf_subnets not read';
  with_settings(sub { run_with_vrfs(instances_complete => undef) }, ignore_private_nets => 0);
  is calls(), $todays, 'an unsupported class behaves as with the switch off';
};

subtest 'arpnip_subnets__vrf_on__upsert_carries_vrf_and_router' => sub {
  my ($job) = run_with_vrfs();
  isnt $job->status, 'error', 'no error';
  is calls(), join(' ', sort
    '198.51.100.0/24||192.0.2.1', '203.0.113.0/24|red|192.0.2.1', '2001:db8:40:0:0:0:0:0/64|red|192.0.2.1'),
    'each subnet stored under its VRF with the polled device as router';
  ok !$last_snmp->{reads}{ip_netmask}, 'today\'s ip_netmask not read';
};

subtest 'arpnip_subnets__private_filter__still_applies_per_vrf' => sub {
  my %fixture = vrf_fixture();
  $fixture{vrf}{red}{subnets} = { subnet('10.40.0.0', 24, 7), subnet('fd00:1::', 64, 7),
    subnet('203.0.113.0', 24, 7) };
  run_with_vrfs(vrf => $fixture{vrf});
  like calls(), qr{10\.40\.0\.0/24\|red}, 'private subnets kept by default';
  run_with_vrfs(vrf => $fixture{vrf}, settings => { ignore_private_nets => 1 });
  is calls(), '198.51.100.0/24||192.0.2.1 203.0.113.0/24|red|192.0.2.1',
    'ignore_private_nets drops rfc1918 and fc00::/7 in a VRF';
};

subtest 'arpnip_subnets__host_loopback_and_link_local__not_stored' => sub {
  my %fixture = vrf_fixture();
  $fixture{vrf}{red}{subnets} = {
    subnet('203.0.113.7', 32, 7), subnet('0.0.0.0', 0, undef), subnet('127.0.0.0', 8, 9),
    subnet('2001:db8:40::1', 128, 7), subnet('::', 0, undef), subnet('fe80::', 64, 7),
    subnet('::1', 128, 9), subnet('203.0.113.0', 24, 7),
  };
  run_with_vrfs(vrf => $fixture{vrf});
  is calls(), '198.51.100.0/24||192.0.2.1 203.0.113.0/24|red|192.0.2.1', 'only the real subnet survives';
};

subtest 'arpnip_subnets__route_only_prefix_without_ifindex__stored' => sub {
  my %fixture = vrf_fixture();
  $fixture{vrf}{red}{subnets} = { subnet('203.0.113.0', 24, undef) };
  run_with_vrfs(vrf => $fixture{vrf});
  like calls(), qr{203\.0\.113\.0/24\|red}, 'a prefix with no ifindex is stored';
};

subtest 'arpnip_subnets__incomplete_vrf__stores_none' => sub {
  my %fixture = vrf_fixture();
  $fixture{vrf}{red}{complete} = 0;
  run_with_vrfs(vrf => $fixture{vrf});
  is calls(), '198.51.100.0/24||192.0.2.1', 'red stores none, default still stored';
};

subtest 'arpnip_subnets__ipv6_vrf_subnet__stored_with_vrf' => sub {
  run_with_vrfs();
  my @v6 = grep { $_->[0] =~ m/:/ } @upserts;
  is scalar(@v6), 1, 'one IPv6 subnet';
  is "$v6[0][0]|$v6[0][2]", '2001:db8:40:0:0:0:0:0/64|red', 'network form (PostgreSQL cidr normalizes it) and VRF';
};

subtest 'arpnip_subnets__second_job_in_one_process__no_subnets_from_the_first' => sub {
  run_with_vrfs();
  ok scalar(@upserts), 'first job stores subnets';
  my %fixture = vrf_fixture();
  run_with_vrfs(vrf => { default => { complete => 1, subnets => {} },
                         red => { complete => 1, subnets => {} } });
  is calls(), '', 'the second job stores nothing of the first';
};

subtest 'arpnip_subnets__cli_driver__module_loads_its_transport' => sub {
  my $out = `$^X -Ilib -e 'use App::Netdisco; use App::Netdisco::Worker::Plugin::Arpnip::Subnets (); print App::Netdisco::Transport::SSH->can("session_for") ? "yes" : "no"' 2>&1`;
  like $out, qr/yes$/, 'Transport::SSH is loaded by the module itself';
};

done_testing;
