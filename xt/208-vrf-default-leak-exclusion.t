#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Util::VRF 'each_vrf_instance';
use Dancer qw/:script !pass/;

# On Juniper the default instance's SNMP read also returns every virtual
# router's rows, so with store_vrfs on it was never whole and the default
# table never updated or retired. SNMP::Info 3.985001 names the instances
# mixed in (vrf_read_leaked) and drops their ports from the default readers
# once told them (vrf_exclude_ports), so each_vrf_instance reads the default
# instance a second time with those ports excluded.

config->{'enable_incomplete_walk_protection'} = 1;

package FakeSession;
sub new { my ($class, $snmp) = @_; return bless { snmp => $snmp }, $class }
sub get {
  my ($self) = @_;
  my $snmp = $self->{snmp};
  if (($snmp->{answers}{ $snmp->{context} } || '') eq 'timeout') {
    @$self{qw/ErrorStr ErrorNum/} = ('Timeout', -24);
    return undef;
  }
  @$self{qw/ErrorStr ErrorNum/} = ('', 0);
  return 12345;
}

# Context switching, walk records and error() as in xt/205. Has neither
# vrf_read_leaked nor vrf_exclude_ports, as SNMP::Info before 3.985001.
package FakeSNMP;
sub new {
  my ($class, %vals) = @_;
  my $self = bless { context => '', walk_failures => [], updates => 0, excluded => {},
                     exclusions => [], complete => {}, %vals }, $class;
  $self->{session} = FakeSession->new($self);
  return $self;
}
sub snmp_ver { 2 }
sub snmp_comm { 'public' }
sub class { 'SNMP::Info::Layer3::Fake' }
sub session { $_[0]{session} }
sub walk_failures { $_[0]{walk_failures} }
sub error { my $self = shift; my $error = $self->{error}; $self->{error} = undef; return $error }
sub update {
  my ($self, %args) = @_;
  my $target = ($args{Community} =~ m/\@(.+)$/ ? $1 : '');
  # SNMP::Info::update() keeps the old session and returns false on failure
  return if $self->{fail_update_to}{$target};
  $self->{context} = $target;
  $self->{updates}++;
  # update() calls clear_cache(), which forgets recorded exclusions
  $self->{excluded} = {};
  return $self->{session};
}
sub vrf_read_complete {
  my ($self, $name) = @_;
  return ($self->{complete}{$name} // 1) unless $name eq 'default';
  return 1 unless $self->{leaks};
  return (grep { not $self->{excluded}{$_} } @{ $self->{leaks} }) ? 0 : 1;
}
sub i_vrf {
  my $self = shift;
  my $context = $self->{context};
  push @{ $self->{walk_failures} }, { method => 'i_vrf', complete => 0, reason => 'timeout' }
    if $self->{short_i_vrf}{$context};
  return $self->{i_vrf}{$context} || {};
}

package FakeLeakSNMP;
our @ISA = ('FakeSNMP');
sub vrf_read_leaked {
  my ($self, $name) = @_;
  return undef unless $name eq 'default' and $self->{leaks} and $self->{context} eq '';
  return [ sort grep { not $self->{excluded}{$_} } @{ $self->{leaks} } ];
}
sub vrf_exclude_ports {
  my ($self, $name, $ports) = @_;
  push @{ $self->{exclusions} },
    { name => $name, ports => [@$ports], context => $self->{context}, updates => $self->{updates} };
  if ($self->{refuse_exclusion}) { $self->{error} = 'refused'; return undef }
  $self->{excluded}{$name} = 1;
  return 1;
}

package main;

my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });

sub switched { my $name = shift;
  return { name => $name, contexts => [{ kind => 'vrf', id => $name, v2c => "%s\@$name", v3 => $name }] } }
my %instances = (
  default => { name => 'default', contexts => [{ kind => 'none' }] },
  blue    => switched('blue'),
  red     => switched('red'),
);

sub run_each {
  my ($snmp, $instances) = @_;
  my @read;
  my $reads = each_vrf_instance($device, $snmp, ($instances || \%instances),
    sub { my ($name) = @_; push @read, [$name, $snmp->{context}]; return "data of $name" });
  return ($reads, \@read);
}

sub default_reads { scalar grep { $_->[0] eq 'default' } @{ $_[0] } }

my %red_ports = (i_vrf => { red => { 12 => 'red', 11 => 'red' }, blue => { 21 => 'blue' } });

subtest 'each_vrf_instance__leaked_instance_read_whole__excludes_ports_and_rereads_default' => sub {
  my $snmp = FakeLeakSNMP->new(leaks => ['red'], %red_ports);
  my ($reads, $read) = run_each($snmp);
  is(scalar @{ $snmp->{exclusions} }, 1, 'one exclusion recorded');
  my ($exclusion) = @{ $snmp->{exclusions} };
  is_deeply($exclusion->{ports}, [11, 12], "red's whole port set, sorted");
  is($exclusion->{name}, 'red', 'for red');
  is($exclusion->{context}, '', 'recorded in the default context');
  is($exclusion->{updates}, $snmp->{updates}, 'after the last update()');
  is(default_reads($read), 2, 'default read again');
  is_deeply([ grep { $_->[0] eq 'default' } @$read ], [['default', ''], ['default', '']],
    'both default reads in the default context');
  is_deeply($reads->{''}, { complete => 1, data => 'data of default' }, 'default now whole');
  is_deeply($reads->{red}, { complete => 1, data => 'data of red' }, 'red read as before');
  is($snmp->{context}, '', 'session ends in the default context');
};

subtest 'each_vrf_instance__leaked_context_dead__default_stays_partial' => sub {
  my $snmp = FakeLeakSNMP->new(leaks => ['red'], answers => { red => 'timeout' }, %red_ports);
  my ($reads, $read) = run_each($snmp);
  is_deeply($snmp->{exclusions}, [], 'no exclusion');
  is(default_reads($read), 1, 'default read once');
  is($reads->{''}{complete}, 0, 'default stays partial');
};

subtest 'each_vrf_instance__leaked_read_short__default_stays_partial' => sub {
  my $snmp = FakeLeakSNMP->new(leaks => ['red'], complete => { red => 0 }, %red_ports);
  my ($reads, $read) = run_each($snmp);
  is_deeply($snmp->{exclusions}, [], 'no exclusion');
  is(default_reads($read), 1, 'default read once');
  is($reads->{''}{complete}, 0, 'default stays partial');
};

subtest 'each_vrf_instance__i_vrf_walk_short__default_stays_partial' => sub {
  my $snmp = FakeLeakSNMP->new(leaks => ['red'], short_i_vrf => { red => 1 }, %red_ports);
  my ($reads, $read) = run_each($snmp);
  is_deeply($snmp->{exclusions}, [], 'no exclusion from a short port walk');
  is(default_reads($read), 1, 'default read once');
  is($reads->{''}{complete}, 0, 'default stays partial');
};

subtest 'each_vrf_instance__leaked_instance_without_context__default_stays_partial' => sub {
  my $snmp = FakeLeakSNMP->new(leaks => ['red'], %red_ports);
  my ($reads, $read) = run_each($snmp, { %instances, red => { name => 'red', contexts => [] } });
  is_deeply($snmp->{exclusions}, [], 'no exclusion');
  is(default_reads($read), 1, 'default read once');
  is($reads->{''}{complete}, 0, 'default stays partial');
};

subtest 'each_vrf_instance__class_does_not_leak__one_default_read' => sub {
  my $snmp = FakeLeakSNMP->new(%red_ports);
  my ($reads, $read) = run_each($snmp);
  is_deeply($snmp->{exclusions}, [], 'no exclusion');
  is(default_reads($read), 1, 'default read once');
  is_deeply($reads->{''}, { complete => 1, data => 'data of default' }, 'default whole as before');
  ok(!(grep { $_->{method} eq 'i_vrf' } @{ $snmp->{walk_failures} }), 'no port walk issued');
};

subtest 'each_vrf_instance__older_snmp_info__unchanged' => sub {
  my $snmp = FakeSNMP->new(leaks => ['red'], %red_ports);
  my ($reads, $read) = run_each($snmp);
  is(default_reads($read), 1, 'default read once');
  is($reads->{''}{complete}, 0, 'default partial, as before 3.985001');
  is($snmp->{updates}, 3, 'two switches and one return, as before');
};

subtest 'each_vrf_instance__exclusion_refused__keeps_first_read' => sub {
  my $snmp = FakeLeakSNMP->new(leaks => ['red'], refuse_exclusion => 1, %red_ports);
  my @logged;
  no warnings 'redefine';
  local *App::Netdisco::Util::VRF::debug = sub { push @logged, "@_" };
  my ($reads, $read) = run_each($snmp);
  is(default_reads($read), 1, 'default not read again');
  is($reads->{''}{complete}, 0, 'default stays partial');
  ok((grep { m/default read stays partial/ and m/refused/ } @logged), 'the refusal is logged with its error');
};

sub logged_run {
  my ($snmp, $instances) = @_;
  my @logged;
  no warnings 'redefine';
  local *App::Netdisco::Util::VRF::debug = sub { push @logged, "@_" };
  my ($reads, $read) = run_each($snmp, $instances);
  return ($reads, \@logged);
}

subtest 'each_vrf_instance__leaked_default_completed__no_incomplete_line' => sub {
  my ($reads, $logged) = logged_run(FakeLeakSNMP->new(leaks => ['red'], %red_ports));
  is($reads->{''}{complete}, 1, 'default whole');
  ok(!(grep { m/VRF default read incomplete/ } @$logged), 'the first read is not reported as kept partial');
};

subtest 'each_vrf_instance__older_snmp_info__incomplete_line_kept' => sub {
  my (undef, $logged) = logged_run(FakeSNMP->new(leaks => ['red'], %red_ports));
  ok((grep { m/VRF default read incomplete, keeping its rows/ } @$logged), 'logged as before');
};

subtest 'each_vrf_instance__leaked_instance_skipped__default_partial_and_named_as_skipped' => sub {
  my %without_blue = %instances; delete $without_blue{blue};
  my $snmp = FakeLeakSNMP->new(leaks => ['blue', 'red'], %red_ports);
  my ($reads, $logged) = logged_run($snmp, \%without_blue);
  is_deeply($snmp->{exclusions}, [], 'no exclusion');
  is($reads->{''}{complete}, 0, 'default stays partial');
  ok((grep { m/default read stays partial: blue is not collected/ } @$logged), 'the skip is named as the cause');
  ok(!(grep { m/blue not read whole/ } @$logged), 'not reported as a failed read');
};

# the guard is dismissed only once the session is back in default, so a failed
# return still drops the cached reader instead of leaving it in a VRF context
subtest 'each_vrf_instance__return_to_default_fails__first_read_stands_and_session_dropped' => sub {
  my $snmp = FakeLeakSNMP->new(leaks => ['red'], fail_update_to => { '' => 1 }, %red_ports);
  my $readers = App::Netdisco::Transport::SNMP->instance->readers;
  $readers->{ $device->ip } = $snmp;
  my ($reads, $read) = do { no warnings 'redefine'; local *App::Netdisco::Util::VRF::warning = sub {}; run_each($snmp) };
  is_deeply($snmp->{exclusions}, [], 'no exclusion recorded outside the default context');
  is(default_reads($read), 1, 'default read once');
  is($reads->{''}{complete}, 0, 'default stays partial');
  ok(!exists $readers->{ $device->ip }, 'cached reader dropped, so the next reader_for reconnects');
};

done_testing;
