#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Util::VRF 'each_vrf_instance';
use App::Netdisco::Transport::SNMP ();
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
  if (ref $answer) {
    @$self{qw/ErrorStr ErrorNum/} = @$answer;
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
sub error { my $self = shift; my $error = $self->{error}; $self->{error} = undef; return $error }
sub vrf_read_complete { 1 }
sub update {
  my ($self, %args) = @_;
  my $target = ($args{Community} =~ m/\@(.+)$/ ? $1 : '');
  # SNMP::Info::update() keeps the old session and returns false on failure
  if ($self->{fail_update_to}{$target}) {
    $self->{error} = $self->{update_error} if exists $self->{update_error};
    return;
  }
  $self->{context} = $target;
  return $self->{session} || 1;
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

subtest 'each_vrf_instance__switch_fails__vrf_incomplete_reader_not_called' => sub {
  my $snmp = FakeSNMP->new(fail_update_to => { red => 1 });
  my ($reads, $read) = run_each($snmp);
  is_deeply $reads->{red}, { complete => 0, data => undef }, 'red incomplete with no data';
  ok !(grep { $_->[0] eq 'red' } @$read), 'red reader not called';
  ok !(grep { $_->[0] eq 'blue' and $_->[1] ne 'blue' } @$read), 'blue read only in its own context';
  is_deeply $reads->{blue}, { complete => 1, data => 'data of blue' }, 'blue still read';
};

sub logged_by_each {
  my ($snmp, $instances) = @_;
  my @logged;
  no warnings 'redefine';
  local *App::Netdisco::Util::VRF::debug = sub { push @logged, "debug:@_" };
  local *App::Netdisco::Util::VRF::warning = sub { push @logged, "warning:@_" };
  each_vrf_instance($device, $snmp, $instances || \%instances, sub { 'data' });
  return @logged;
}

subtest 'each_vrf_instance__switch_update_fails__logged_apart_from_no_context_with_error' => sub {
  my $error = 'SNMP::Info::update() Net-SNMP session creation failed. no route';
  my @logged = logged_by_each(FakeSNMP->new(fail_update_to => { red => 1 }, update_error => $error));
  is_deeply [ grep { m/VRF red/ } @logged ],
    [ "debug: [192.0.2.1] device - VRF red could not be switched to, update() failed: $error" ],
    'failed update named, with the error';
  @logged = logged_by_each(FakeSNMP->new(fail_update_to => { red => 1 }));
  is_deeply [ grep { m/VRF red/ } @logged ],
    [ 'debug: [192.0.2.1] device - VRF red could not be switched to, update() failed' ],
    'no error to append';
  my %refused = (%instances,
    red => { name => 'red', contexts => [{ kind => 'vrf', id => 'red', v2c => undef, v3 => 'red' }] });
  @logged = logged_by_each(FakeSNMP->new, \%refused);
  is_deeply [ grep { m/VRF red/ } @logged ],
    [ 'debug: [192.0.2.1] device - VRF red has no context this session can reach' ],
    'a class refusing community suffixes keeps its own text';
};

subtest 'each_vrf_instance__return_to_default_fails__warning_carries_error' => sub {
  my @logged = logged_by_each(FakeSNMP->new(fail_update_to => { '' => 1 }, update_error => 'timeout'));
  is_deeply [ grep { m/^warning:/ } @logged ],
    [ 'warning: [192.0.2.1] device - could not return to the default context, so the SNMP session is dropped: timeout' ],
    'error appended';
  @logged = logged_by_each(FakeSNMP->new(fail_update_to => { '' => 1 }));
  is_deeply [ grep { m/^warning:/ } @logged ],
    [ 'warning: [192.0.2.1] device - could not return to the default context, so the SNMP session is dropped' ],
    'unchanged with no error';
};

# the reader is cached for the job, so later workers would read the VRF's
# context as the default one
subtest 'each_vrf_instance__return_to_default_fails__cached_reader_dropped' => sub {
  my $snmp = FakeSNMP->new(fail_update_to => { '' => 1 });
  my $readers = App::Netdisco::Transport::SNMP->instance->readers;
  $readers->{ $device->ip } = $snmp;
  run_each($snmp);
  is $snmp->{context}, 'red', 'session left in the last VRF context';
  ok !exists $readers->{ $device->ip }, 'cached reader dropped, so the next reader_for reconnects';
};

subtest 'each_vrf_instance__return_to_default_succeeds__cached_reader_kept' => sub {
  my $snmp = FakeSNMP->new;
  my $readers = App::Netdisco::Transport::SNMP->instance->readers;
  $readers->{ $device->ip } = $snmp;
  run_each($snmp);
  is $readers->{ $device->ip }, $snmp, 'cached reader kept';
  delete $readers->{ $device->ip };
};

# only the same object is dropped: a reader cached since by another worker is
# a fresh session in the default context
subtest 'each_vrf_instance__return_fails_other_reader_cached__other_reader_kept' => sub {
  my $snmp = FakeSNMP->new(fail_update_to => { '' => 1 });
  my $other = FakeSNMP->new;
  my $readers = App::Netdisco::Transport::SNMP->instance->readers;
  $readers->{ $device->ip } = $other;
  run_each($snmp);
  is $snmp->{context}, 'red', 'session left in the last VRF context';
  is $readers->{ $device->ip }, $other, 'the different cached object is kept';
  delete $readers->{ $device->ip };
};

subtest 'each_vrf_instance__return_fails_nothing_cached__no_reader_added' => sub {
  my $snmp = FakeSNMP->new(fail_update_to => { '' => 1 });
  my $readers = App::Netdisco::Transport::SNMP->instance->readers;
  delete $readers->{ $device->ip };
  run_each($snmp);
  ok !exists $readers->{ $device->ip }, 'no cache entry created for the device';
};

subtest 'each_vrf_instance__reader_dies__restored_and_error_propagated' => sub {
  my $snmp = FakeSNMP->new;
  my $readers = App::Netdisco::Transport::SNMP->instance->readers;
  $readers->{ $device->ip } = $snmp;
  my $ok = eval { each_vrf_instance($device, $snmp, \%instances,
    sub { die "reader died\n" if $_[0] eq 'blue'; return 'data' }); 1 };
  is $@, "reader died\n", 'the reader error propagates';
  is $snmp->{context}, '', 'session back in the default context after the unwind';
  is $readers->{ $device->ip }, $snmp, 'cached reader kept';
  delete $readers->{ $device->ip };
};

subtest 'each_vrf_instance__reader_dies_return_fails__reader_dropped_error_kept' => sub {
  my $snmp = FakeSNMP->new(fail_update_to => { '' => 1 });
  my $readers = App::Netdisco::Transport::SNMP->instance->readers;
  $readers->{ $device->ip } = $snmp;
  my $ok = eval { each_vrf_instance($device, $snmp, \%instances,
    sub { die "reader died\n" if $_[0] eq 'blue'; return 'data' }); 1 };
  is $@, "reader died\n", 'the reader error is not replaced by the guard';
  ok !exists $readers->{ $device->ip }, 'cached reader dropped on the unwind path';
};

# an error that is not a timeout is the agent answering; representative
# ErrorStr text for a v3 unknownContexts report and a v1 noSuchName reply
foreach my $case (
  [ 'v3_unknown_contexts_report' => [ 'Unknown Context', -2 ] ],
  [ 'v1_no_such_name' => [ '(noSuchName) There is no such variable name in this MIB.', 2 ] ],
  [ 'generic_error' => [ 'genErr', 5 ] ],
) {
  my ($label, $answer) = @$case;
  subtest "each_vrf_instance__context_answers_${label}__read_as_usual" => sub {
    my $snmp = FakeSNMP->new(answers => { red => $answer });
    my ($reads, $read) = run_each($snmp);
    is_deeply $reads->{red}, { complete => 1, data => 'data of red' }, 'red read and complete';
    is_deeply [grep { $_->[0] eq 'red' } @$read], [['red', 'red']], 'red read in its context';
  };
}

subtest 'each_vrf_instance__timeout_in_longer_error_text__vrf_incomplete' => sub {
  my $snmp = FakeSNMP->new(answers => { red => [ 'Timeout: No Response from 192.0.2.1', -24 ] });
  my ($reads) = run_each($snmp);
  is_deeply $reads->{red}, { complete => 0, data => undef }, 'red incomplete with no data';
};

subtest 'each_vrf_instance__session_without_get__context_counts_as_answering' => sub {
  my $snmp = FakeSNMP->new;
  $snmp->{session} = undef;
  my ($reads) = run_each($snmp);
  is_deeply $reads->{red}, { complete => 1, data => 'data of red' }, 'red read with no probe possible';
  is_deeply $snmp->{probes}, [], 'nothing probed';
};

subtest 'each_vrf_instance__session_without_get_method__context_counts_as_answering' => sub {
  my $snmp = FakeSNMP->new;
  $snmp->{session} = bless {}, 'NoGetSession';
  my ($reads) = run_each($snmp);
  is_deeply $reads->{red}, { complete => 1, data => 'data of red' }, 'red read with no probe possible';
};

done_testing;
