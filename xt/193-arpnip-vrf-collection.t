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
use App::Netdisco::Worker::Plugin::Arpnip::Nodes ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The SNMP arpnip worker with store_vrfs on, run through the Runner as xt/192
# runs discover: SNMP is faked and store_arp records the entries it is given.
# The fake answers a VRF's neighbors only in that VRF's context, so a read in
# the wrong context returns nothing, as SNMP::Info does.

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
config->{'dns'}->{'no'} = ['0.0.0.0/0'];

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
sub _in_default { return $_[0]{context} eq '' }

sub vrf_instances {
  my $self = shift;
  $self->{reads}{vrf_instances}++;
  return $self->_in_default ? $self->{instances} : undef;
}
sub vrf_instances_complete {
  my $self = shift;
  $self->{reads}{vrf_instances_complete}++;
  push @{ $self->{list_complete_read_in} }, $self->{context};
  return $self->_in_default ? $self->{instances_complete} : undef;
}
sub _vrf_answer {
  my ($self, $what, $name) = @_;
  push @{ $self->{vrf_reads}{$name} }, $what;
  return undef unless $self->{context} eq $self->_context_of($name);
  return $self->{vrf}{$name}{$what};
}
sub vrf_neighbors {
  my ($self, $name) = @_;
  # a cut-short walk records itself, as SNMP::Info's walk_failures does
  push @{ $self->{walk_failures} }, $self->{fail_neighbors_in}{$name}
    if $self->{fail_neighbors_in}{$name};
  return $self->_vrf_answer('neighbors', $name);
}
sub vrf_read_complete { $_[0]->_vrf_answer('complete', $_[1]) }

sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  $self->{reads}{$method}++;
  return $self->{$method};
}

package main;

my %device_cols = (
  ip => '192.0.2.1', name => 'router1', layers => '00000100', snmp_ver => 2,
  snmp_class => 'SNMP::Info::Layer3',
);

# today's tables: one IPv4 ARP entry and one IPv6 neighbor
my %base_snmp = (
  class => 'SNMP::Info::Layer3',
  at_paddr   => { '1.192.0.2.10' => '00:11:22:33:44:01' },
  at_netaddr => { '1.192.0.2.10' => '192.0.2.10' },
  ipv6_n2p_mac  => { '1.16.32.1.13.184.0.0.0.0.0.0.0.0.0.0.0.16' => '00:11:22:33:44:02' },
  ipv6_n2p_addr => { '1.16.32.1.13.184.0.0.0.0.0.0.0.0.0.0.0.16' => '2001:db8::10' },
);

sub context_record { my $name = shift;
  return [{ kind => 'vrf', id => $name, v2c => "%s\@$name", v3 => $name }] }

sub instance {
  my ($name, %over) = @_;
  return {
    name => $name, kind => ($name eq 'default' ? 'default' : 'vrf'),
    contexts => ($name eq 'default' ? [{ kind => 'none' }] : context_record($name)),
    %over,
  };
}

sub neighbor { my ($ifindex, $ip, $mac) = @_;
  return ("$ifindex.$ip" => { ifindex => $ifindex, ip => $ip, mac => $mac,
    family => ($ip =~ m/:/ ? 'ipv6' : 'ipv4') }) }

# default, red and blue each hold one neighbor; red and blue share an address
sub vrf_fixture {
  return (
    instances_complete => 1,
    instances => {
      default => instance('default'),
      red  => instance('red'),
      blue => instance('blue'),
    },
    vrf => {
      default => { complete => 1, neighbors => { neighbor(1, '192.0.2.10', '00:11:22:33:44:01') } },
      red  => { complete => 1, neighbors => { neighbor(7, '10.40.0.5', '00:11:22:33:44:07'),
                                              neighbor(7, '2001:db8:40::5', '00:11:22:33:44:17') } },
      blue => { complete => 1, neighbors => { neighbor(8, '10.40.0.5', '00:11:22:33:44:08') } },
    },
  );
}

our @stored;
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

sub run_arpnip {
  my (%snmp) = @_;
  # vrf_read and vrf_list_complete are left for the early worker to clear, as
  # netdisco-do runs every job in one process
  delete @{ vars() }{qw/arps timestamp hook_data/};
  @stored = ();
  my $device_over = delete $snmp{device} || {};

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols, %$device_over });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_arpnip'} = 0;

  my $fake_snmp = FakeSNMP->new(%base_snmp, %snmp);
  $last_snmp = $fake_snmp;
  no warnings 'once';

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::store_arp = sub { push @stored, { %{ $_[0] } } };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::retire_unvouched_arps = sub { 0 };
  # the store phase looks up the device's own MACs and addresses; xt/203 covers that
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::own_identity = sub { return ({}, {}, {}) };
  local *App::Netdisco::DB::Result::Device::update = sub { return $_[0] };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'arpnip::nodes',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

sub run_with_vrfs {
  my (%snmp) = @_;
  my $settings = delete $snmp{settings} || {};
  return with_settings(sub { run_arpnip(vrf_fixture(), %snmp) }, store_vrfs => 1, %$settings);
}

sub entries { return join ' ', sort map { join '|', $_->{ip}, $_->{mac}, $_->{vrf} // '-' } @stored }
sub in_vrf { my $vrf = shift; return grep { defined $_->{vrf} and $_->{vrf} eq $vrf } @stored }

my $todays = do { with_settings(sub { run_arpnip() }, store_vrfs => 0); [ sort { $a->{ip} cmp $b->{ip} } @stored ] };

subtest 'arpnip__switch_off__today_entries_and_no_vrf_read' => sub {
  is_deeply $todays, [
    { mac => '00:11:22:33:44:01', ip => '192.0.2.10', dns => undef },
    { mac => '00:11:22:33:44:02', ip => '2001:db8::10', dns => undef },
  ], 'the expectation holds today\'s ARP and neighbor entries';
  with_settings(sub { run_arpnip(vrf_fixture()) }, store_vrfs => 0);
  is_deeply [ sort { $a->{ip} cmp $b->{ip} } @stored ], $todays, 'entries as today';
  ok !$last_snmp->{reads}{vrf_instances}, 'vrf_instances not read';
  ok !$last_snmp->{vrf_reads}, 'vrf_neighbors not read';
  ok !exists vars->{'vrf_read'}, 'no vrf_read';
  ok !exists vars->{'vrf_list_complete'}, 'no vrf_list_complete';
};

# a snapshot read offline: update() would clear the snapshot from the cache
subtest 'arpnip__offline_snapshot_device__flat_read_and_no_update' => sub {
  my ($job) = run_with_vrfs(offline => 1, device => { is_pseudo => 1 });
  is $job->status, 'done', 'arpnip done';
  is_deeply [ sort { $a->{ip} cmp $b->{ip} } @stored ], $todays, 'entries as with the switch off';
  ok !$last_snmp->{reads}{vrf_instances}, 'vrf_instances not read';
  ok !$last_snmp->{reads}{vrf_instances_complete}, 'vrf_instances_complete not read';
  ok !$last_snmp->{vrf_reads}, 'vrf_neighbors not read';
  is_deeply $last_snmp->{contexts_asked}, [], 'no update() call';
  ok !exists vars->{'vrf_read'}, 'no vrf_read';
};

subtest 'arpnip__unsupported_class__today_entries_and_no_vrf_read' => sub {
  run_with_vrfs(instances_complete => undef);
  is_deeply [ sort { $a->{ip} cmp $b->{ip} } @stored ], $todays, 'entries as with the switch off';
  ok !$last_snmp->{reads}{vrf_instances}, 'vrf_instances not read';
  ok !exists vars->{'vrf_read'}, 'no vrf_read';
  ok !exists vars->{'vrf_list_complete'}, 'no vrf_list_complete';
};

subtest 'arpnip__two_vrfs_same_ip_other_mac__both_entries_kept' => sub {
  my ($job) = run_with_vrfs();
  is $job->status, 'done', 'arpnip done';
  is entries(), join(' ', sort
    '10.40.0.5|00:11:22:33:44:07|red', '10.40.0.5|00:11:22:33:44:08|blue',
    '192.0.2.10|00:11:22:33:44:01|', '2001:db8:40::5|00:11:22:33:44:17|red'),
    'one entry per VRF, default stored as empty vrf';
  ok !$last_snmp->{reads}{at_paddr}, 'today\'s ARP table not read';
  ok !$last_snmp->{reads}{ipv6_n2p_mac}, 'today\'s neighbor table not read';
  my ($red) = grep { $_->{mac} eq '00:11:22:33:44:07' } @stored;
  is_deeply [ sort keys %$red ], [qw/dns ip mac vrf/], 'entry keys';
  ok !defined $red->{dns}, 'dns left to the resolver';
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 1, blue => 1 }, 'every VRF read whole';
  is_deeply $last_snmp->{contexts_asked}, [ 'blue', 'red', '' ],
    'default read without a switch, then names sorted, then one restore';
};

subtest 'arpnip__same_ip_and_mac_two_vrfs__two_entries' => sub {
  my %fixture = vrf_fixture();
  $fixture{vrf}{blue}{neighbors} = { neighbor(8, '10.40.0.5', '00:11:22:33:44:07') };
  run_with_vrfs(vrf => $fixture{vrf});
  my @shared = grep { $_->{ip} eq '10.40.0.5' } @stored;
  is join(' ', sort map { $_->{vrf} } @shared), 'blue red', 'one entry in each VRF';
  is scalar(grep { $_->{mac} eq '00:11:22:33:44:07' } @shared), 2, 'same MAC in both';
};

subtest 'arpnip__short_vrf_walk__marked_incomplete' => sub {
  my %fixture = vrf_fixture();
  $fixture{vrf}{blue}{complete} = 0;
  run_with_vrfs(vrf => $fixture{vrf}, fail_neighbors_in => { red => {
    method => 'vrf_neighbors', leaf => 'IP-MIB::ipNetToPhysicalPhysAddress', reason => 'timeout',
    rows => 1, walk => 'bulkwalk', complete => 0, context => 'red' } });
  is vars->{'vrf_read'}{blue}, 0, 'vrf_read_complete 0 marks blue incomplete';
  is vars->{'vrf_read'}{red}, 0, 'a short walk marks red incomplete';
  is vars->{'vrf_read'}{''}, 1, 'default unaffected';
  ok scalar(in_vrf('blue')), 'entries read from blue still stored';
};

subtest 'arpnip__context_unreachable__recorded_incomplete_not_read' => sub {
  my %fixture = vrf_fixture();
  $fixture{instances}{blue}{contexts} = [{ kind => 'vrf', id => 'blue', v2c => undef, v3 => 'blue' }];
  run_with_vrfs(instances => $fixture{instances});
  ok !$last_snmp->{vrf_reads}{blue}, 'blue never read';
  ok !(grep { $_ eq 'blue' } @{ $last_snmp->{contexts_asked} }), 'never switched to blue';
  is vars->{'vrf_read'}{blue}, 0, 'blue recorded as incomplete';
  is scalar(in_vrf('blue')), 0, 'no blue entries';
  is vars->{'vrf_read'}{red}, 1, 'red read';
};

subtest 'arpnip__empty_contexts__recorded_incomplete_not_read' => sub {
  my %fixture = vrf_fixture();
  $fixture{instances}{blue}{contexts} = [];
  run_with_vrfs(instances => $fixture{instances});
  ok !$last_snmp->{vrf_reads}{blue}, 'blue never read';
  ok !(grep { $_ eq 'blue' } @{ $last_snmp->{contexts_asked} }), 'never switched to blue';
  is vars->{'vrf_read'}{blue}, 0, 'blue recorded as incomplete';
  is scalar(in_vrf('blue')), 0, 'no blue entries';
  is vars->{'vrf_read'}{red}, 1, 'red read';
};

subtest 'arpnip__skipped_vrf__no_entries' => sub {
  run_with_vrfs(settings => { vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:blue' } });
  ok !$last_snmp->{vrf_reads}{blue}, 'blue never read';
  ok !(grep { $_ eq 'blue' } @{ $last_snmp->{contexts_asked} }), 'never switched to blue';
  is scalar(in_vrf('blue')), 0, 'no blue entries';
  ok !exists vars->{'vrf_read'}{blue}, 'blue absent from vrf_read';
  ok scalar(in_vrf('red')), 'red entries stored';
};

subtest 'arpnip__attribution_mode__no_update_calls' => sub {
  my %fixture = vrf_fixture();
  my %instances = map { ($_ => { %{ $fixture{instances}{$_} }, contexts => [{ kind => 'none' }] }) }
    keys %{ $fixture{instances} };
  run_with_vrfs(instances => \%instances);
  is_deeply $last_snmp->{contexts_asked}, [], 'no update() at all';
  ok scalar(in_vrf('red')), 'red read in the default context';
  ok scalar(in_vrf('blue')), 'blue read in the default context';
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 1, blue => 1 }, 'every VRF read whole';
};

subtest 'arpnip__vrf_list_short__vrf_list_complete_zero' => sub {
  run_with_vrfs();
  is vars->{'vrf_list_complete'}, 1, 'a complete list records 1';
  run_with_vrfs(instances_complete => 0);
  is vars->{'vrf_list_complete'}, 0, 'a short list records 0';
  ok scalar(in_vrf('red')), 'the listed VRFs still read';
  ok !(grep { $_ ne '' } @{ $last_snmp->{list_complete_read_in} }),
    'list completeness read in the default context';
};

subtest 'arpnip__second_job_in_one_process__no_vrf_read_from_the_first' => sub {
  run_with_vrfs();
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 1, blue => 1 }, 'first job reads its VRFs';
  run_with_vrfs(settings => { skip_vrf_devices => ['192.0.2.1'] });
  ok !exists vars->{'vrf_read'}, 'a skipped device leaves no vrf_read';
  ok !exists vars->{'vrf_list_complete'}, 'a skipped device leaves no vrf_list_complete';
  my %fixture = vrf_fixture();
  run_with_vrfs(instances => { default => $fixture{instances}{default}, green => instance('green') },
    vrf => { default => $fixture{vrf}{default},
             green => { complete => 1, neighbors => { neighbor(9, '10.50.0.5', '00:11:22:33:44:09') } } });
  is_deeply vars->{'vrf_read'}, { '' => 1, green => 1 }, 'only the third job\'s VRFs';
};

done_testing;
