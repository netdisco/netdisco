#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Util::VRF 'each_vrf_instance';
use Dancer qw/:script !pass/;

# A v2c community@vrf the device drops costs every attribute a VRF reader
# walks its own SNMP timeout; lab arpnip took 364 s of a 600 s job timeout for
# one dead context. each_vrf_instance asks the switched context for one
# scalar first, and only a timeout stops the read.

config->{'enable_incomplete_walk_protection'} = 1;

package FakeSession;
sub new { my ($class, $snmp) = @_; return bless { snmp => $snmp }, $class }
sub get {
  my ($self, $oid) = @_;
  my $snmp = $self->{snmp};
  push @{ $snmp->{probes} }, [$snmp->{context}, $oid];
  my $answer = $snmp->{answers}{ $snmp->{context} } || 'value';
  if ($answer eq 'timeout') {
    @$self{qw/ErrorStr ErrorNum/} = ('Timeout', -24);
    return undef;
  }
  @$self{qw/ErrorStr ErrorNum/} = ('', 0);
  return ($answer eq 'nosuchobject' ? 'NOSUCHOBJECT' : 12345);
}

package FakeSNMP;
sub new {
  my ($class, %vals) = @_;
  my $self = bless { context => '', probes => [], walk_failures => [], %vals }, $class;
  $self->{session} = FakeSession->new($self);
  return $self;
}
sub snmp_ver { 2 }
sub snmp_comm { 'public' }
sub class { 'SNMP::Info::Layer3::Fake' }
sub session { $_[0]{session} }
sub walk_failures { $_[0]{walk_failures} }
sub error { undef }
sub vrf_read_complete { 1 }
sub update {
  my ($self, %args) = @_;
  $self->{context} = ($args{Community} =~ m/\@(.+)$/ ? $1 : '');
  return 1;
}

package main;

my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });

sub switched { my $name = shift;
  return { name => $name, contexts => [{ kind => 'vrf', id => $name, v2c => "%s\@$name", v3 => $name }] } }
my %instances = (
  default => { name => 'default', contexts => [{ kind => 'none' }] },
  mgmt    => { name => 'mgmt', contexts => [{ kind => 'none' }] },
  blue    => switched('blue'),
  red     => switched('red'),
);

sub run_each {
  my $snmp = shift;
  my @read;
  my $reads = each_vrf_instance($device, $snmp, \%instances,
    sub { my ($name) = @_; push @read, [$name, $snmp->{context}]; return "data of $name" });
  return ($reads, \@read);
}

subtest 'each_vrf_instance__context_times_out__vrf_incomplete_reader_not_called' => sub {
  my $snmp = FakeSNMP->new(answers => { red => 'timeout', blue => 'timeout' });
  my ($reads, $read) = run_each($snmp);
  is_deeply $reads->{red}, { complete => 0, data => undef }, 'red incomplete with no data';
  ok !(grep { $_->[0] eq 'red' } @$read), 'red reader not called';
  is_deeply [grep { $_->[0] eq 'red' } @{ $snmp->{probes} }],
    [['red', '.1.3.6.1.2.1.1.3.0']], 'red asked for sysUpTime.0 once';
  is $snmp->{context}, '', 'session back in the default context';
};

subtest 'each_vrf_instance__context_answers_nosuchobject__read_as_usual' => sub {
  my $snmp = FakeSNMP->new(answers => { red => 'nosuchobject' });
  my ($reads, $read) = run_each($snmp);
  is_deeply $reads->{red}, { complete => 1, data => 'data of red' }, 'red read and complete';
  is_deeply [grep { $_->[0] eq 'red' } @$read], [['red', 'red']], 'red read in its context';
};

subtest 'each_vrf_instance__one_dead_context__other_vrfs_still_read' => sub {
  my $snmp = FakeSNMP->new(answers => { blue => 'timeout' });
  my ($reads, $read) = run_each($snmp);
  is_deeply $reads->{blue}, { complete => 0, data => undef }, 'blue incomplete';
  is_deeply $reads->{red}, { complete => 1, data => 'data of red' }, 'red read after blue';
  is_deeply $reads->{''}, { complete => 1, data => 'data of default' }, 'default read';
  is_deeply $reads->{mgmt}, { complete => 1, data => 'data of mgmt' }, 'in-place mgmt read';
};

subtest 'each_vrf_instance__default_context__not_probed' => sub {
  my $snmp = FakeSNMP->new;
  run_each($snmp);
  is_deeply [map { $_->[0] } @{ $snmp->{probes} }], ['blue', 'red'],
    'only the switched contexts are probed';
};

done_testing;
