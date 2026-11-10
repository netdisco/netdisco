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
use App::Netdisco::Transport::SSH ();
use App::Netdisco::Worker::Plugin::Arpnip::Nodes ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The CLI arpnip worker with store_vrfs on, run through the Runner as xt/193
# runs the SNMP one. session_for is faked to return a session over a stub
# platform, so the worker's contract with a platform is tested without SSH.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

config->{'dns'}->{'no'} = ['0.0.0.0/0'];

# today's platform contract: arpnip returns a flat list, as a site-local
# App::NetdiscoX::SSHCollector::Platform::* module does
package FlatPlatform;
sub new { my ($class, %args) = @_; return bless { calls => [], %args }, $class }
sub arpnip {
  my $self = shift;
  push @{ $self->{calls} }, [ 'arpnip', @_ ];
  return @{ $self->{flat} || [] };
}

package ReportingPlatform;
our @ISA = ('FlatPlatform');
sub arpnip_by_vrf {
  my $self = shift;
  push @{ $self->{calls} }, [ 'arpnip_by_vrf', @_ ];
  die $self->{die} if $self->{die};
  return $self->{by_vrf};
}

package FakeSNMP;
our $AUTOLOAD;
sub new { my ($class, %vals) = @_; return bless { walk_failures => [], %vals }, $class }
sub walk_failures { $_[0]{walk_failures} }
sub walk_status { undef }
sub error { undef }
sub vrf_instances { $_[0]{instances} }
sub vrf_instances_complete { $_[0]{instances_complete} }
sub vrf_neighbors { $_[0]{vrf}{ $_[1] }{neighbors} }
sub vrf_read_complete { $_[0]{vrf}{ $_[1] }{complete} }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  return $self->{$method};
}

package main;

my %device_cols = (
  ip => '192.0.2.1', name => 'router1', layers => '00000100', snmp_ver => 2,
  snmp_class => 'SNMP::Info::Layer3',
);

my @flat = (
  { ip => '192.0.2.10', mac => '00:11:22:33:44:01' },
  { ip => '2001:db8::10', mac => '00:11:22:33:44:02' },
);

sub by_vrf {
  my (%over) = @_;
  return {
    entries => [
      { ip => '192.0.2.10', mac => '00:11:22:33:44:01', vrf => '' },
      { ip => '10.40.0.5',  mac => '00:11:22:33:44:07', vrf => 'red' },
      { ip => '10.40.0.5',  mac => '00:11:22:33:44:08', vrf => 'blue' },
    ],
    vrf_read => { '' => 1, red => 1, blue => 1 },
    vrf_list_complete => 1,
    families => [4, 6],
    %over,
  };
}

# SNMP attribution-mode instances, so every VRF is read with no update()
sub snmp_fixture {
  my (%complete) = @_;
  my %instances = map { ($_ => { name => $_, kind => ($_ eq 'default' ? 'default' : 'vrf'),
                                 contexts => [{ kind => 'none' }] }) } qw/default red blue/;
  return (
    instances_complete => (exists $complete{list} ? $complete{list} : 1),
    instances => \%instances,
    vrf => {
      default => { complete => 1, neighbors => {} },
      red  => { complete => (exists $complete{red} ? $complete{red} : 1),
                neighbors => { '7.10.40.0.5' => { ip => '10.40.0.5', mac => '00:11:22:33:44:07' } } },
      blue => { complete => 1, neighbors => {} },
    },
  );
}

our (@stored, @logged, @informed, @retired, @cli_vrfs);

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

# platform => object (or undef for a failed connection), snmp => FakeSNMP args
sub run_arpnip {
  my (%args) = @_;
  delete @{ vars() }{qw/arps timestamp hook_data/};
  @stored = (); @logged = (); @informed = (); @retired = (); @cli_vrfs = ();

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_arpnip'} = 0;

  my $session = $args{platform}
    ? MySession->new(platform => $args{platform}, host => $device->ip, ssh => 'SSH', auth => { platform => 'Stub' })
    : undef;
  my $fake_snmp = FakeSNMP->new(%{ $args{snmp} || {} });
  no warnings 'once';

  local *App::Netdisco::Transport::SSH::session_for = sub { return $session };
  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::store_arp = sub { push @stored, { %{ $_[0] } } };
  # device_vrf writes need a database; xt/209 covers record_cli_vrfs
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::record_cli_vrfs = sub { push @cli_vrfs, [ { %{ $_[1] } }, $_[2] ]; die "deadlock\n" if $args{record_dies}; 0 };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::retire_unvouched_arps = sub { push @retired, [ @_[2, 3] ]; 0 };
  # the store phase looks up the device's own MACs and addresses; xt/203 covers that
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::own_identity = sub { return ({}, {}, {}) };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::debug = sub { push @logged, join '', @_ };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::info = sub { push @informed, join '', @_ };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::warning = sub { push @logged, join '', @_ };
  local *App::Netdisco::DB::Result::Device::update = sub { return $_[0] };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'arpnip::nodes',
  });

  my $auth = ($args{snmp} ? [{ driver => 'snmp' }, { driver => 'cli' }] : [{ driver => 'cli' }]);
  with_settings(sub {
    try { MyWorker->new()->run($job) }
    catch { $job->status('error'); $job->log("error running job: $_") };
  }, device_auth => $auth, store_vrfs => 1, %{ $args{settings} || {} });

  return $job;
}

sub entries { return join ' ', sort map { join '|', $_->{ip}, $_->{mac}, $_->{vrf} // '-' } @stored }
sub flatten_lines { return grep { m/flatten/ } @logged }
sub calls_of { my ($platform, $name) = @_; return grep { $_->[0] eq $name } @{ $platform->{calls} } }

subtest 'cli_arpnip__switch_off__calls_arpnip_unchanged' => sub {
  my $platform = ReportingPlatform->new(flat => [@flat], by_vrf => by_vrf());
  my $job = run_arpnip(platform => $platform, settings => { store_vrfs => 0 });
  is $job->status, 'done', 'arpnip done';
  is scalar(calls_of($platform, 'arpnip_by_vrf')), 0, 'arpnip_by_vrf not called';
  my ($call) = calls_of($platform, 'arpnip');
  is_deeply $call, [ 'arpnip', '192.0.2.1', 'SSH', { platform => 'Stub' } ], 'arpnip called as today';
  is_deeply [ sort { $a->{ip} cmp $b->{ip} } @stored ], \@flat, 'entries stored as returned';
  is scalar(flatten_lines()), 0, 'no flattening line with the switch off';
  ok !exists vars->{'vrf_read'}, 'no vrf_read';
  ok !exists vars->{'vrf_list_complete'}, 'no vrf_list_complete';
};

subtest 'cli_arpnip__platform_without_arpnip_by_vrf__flattens_and_logs_once' => sub {
  my $platform = FlatPlatform->new(flat => [@flat]);
  my $job = run_arpnip(platform => $platform);
  is $job->status, 'done', 'arpnip done';
  is_deeply [ sort { $a->{ip} cmp $b->{ip} } @stored ], \@flat, 'entries stored as returned';
  is scalar(flatten_lines()), 1, 'one flattening line';
  like((flatten_lines())[0], qr/contributes no VRF reads/, 'the line says this collector reads no VRF');
  like((flatten_lines())[0], qr/192\.0\.2\.1/, 'the line names the device');
  ok !exists vars->{'vrf_read'}, 'no vrf_read, so nothing retires';
  ok !exists vars->{'vrf_list_complete'}, 'no vrf_list_complete';
};

subtest 'cli_arpnip__site_local_flat_platform__works_with_switch_on' => sub {
  my $platform = FlatPlatform->new(flat => [ { ip => '192.0.2.20', mac => '00:11:22:33:44:20', dns => undef } ]);
  my $job = run_arpnip(platform => $platform);
  is $job->status, 'done', 'arpnip done';
  is scalar(calls_of($platform, 'arpnip')), 1, 'arpnip called once';
  is entries(), '192.0.2.20|00:11:22:33:44:20|-', 'entry stored without a vrf';
};

subtest 'cli_arpnip__reporting_platform__entries_keep_vrf' => sub {
  my $platform = ReportingPlatform->new(flat => [@flat], by_vrf => by_vrf());
  my $job = run_arpnip(platform => $platform);
  is $job->status, 'done', 'arpnip done';
  is scalar(calls_of($platform, 'arpnip')), 0, 'flat arpnip not called';
  my ($call) = calls_of($platform, 'arpnip_by_vrf');
  is_deeply $call, [ 'arpnip_by_vrf', '192.0.2.1', 'SSH', { platform => 'Stub' } ],
    'arpnip_by_vrf called with the arpnip arguments';
  is entries(), join(' ', sort '192.0.2.10|00:11:22:33:44:01|',
    '10.40.0.5|00:11:22:33:44:07|red', '10.40.0.5|00:11:22:33:44:08|blue'),
    'one entry per VRF, same IP in two VRFs kept apart';
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 1, blue => 1 }, 'vrf_read from the platform';
  is vars->{'vrf_list_complete'}, 1, 'vrf_list_complete from the platform';
  is scalar(flatten_lines()), 0, 'no flattening line';
};

subtest 'cli_arpnip__default_named_default__stored_as_empty_vrf' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(
    entries => [ { ip => '192.0.2.10', mac => '00:11:22:33:44:01', vrf => 'default' } ],
    vrf_read => { default => 1 }));
  run_arpnip(platform => $platform);
  is entries(), '192.0.2.10|00:11:22:33:44:01|', 'default stored as the empty vrf';
  is_deeply vars->{'vrf_read'}, { '' => 1 }, 'vrf_read keyed by the empty vrf';
};

subtest 'cli_arpnip__skipped_vrf__entries_dropped' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf());
  run_arpnip(platform => $platform, settings => { vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:blue' } });
  is scalar(grep { $_->{vrf} eq 'blue' } @stored), 0, 'no blue entries';
  ok scalar(grep { $_->{vrf} eq 'red' } @stored), 'red entries stored';
  ok !exists vars->{'vrf_read'}{blue}, 'blue absent from vrf_read, so it retires as skipped';
  run_arpnip(platform => $platform, settings => { vrf_no_devicevrfs => { '192.0.2.1' => 'vrf:red' } });
  is scalar(grep { $_->{vrf} eq 'red' } @stored), 0, 'vrf_no_devicevrfs drops red';
};

subtest 'cli_arpnip__vrfs_read__recorded_once_without_skipped' => sub {
  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf()), settings => { vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:blue' } });
  is_deeply \@cli_vrfs, [ [ { '' => 1, red => 1 }, 1 ] ], 'what was read, skipped blue left out, with the list state';
  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf()), settings => { store_vrfs => 0 });
  is_deeply \@cli_vrfs, [], 'nothing recorded with the switch off';
  run_arpnip(platform => FlatPlatform->new(flat => [@flat]));
  is_deeply \@cli_vrfs, [], 'nothing recorded for a collector that reads no VRF';
};

subtest 'cli_arpnip__recording_vrfs_fails__entries_still_retired_and_job_done' => sub {
  my $job = run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf()), record_dies => 1);
  is $job->status, 'done', 'arpnip done';
  is scalar(@retired), 1, 'retirement still ran';
  ok scalar(grep { m/recording the VRFs read failed.*deadlock/ } @logged), 'the failure is logged';
};

subtest 'cli_arpnip__one_vrf_incomplete__others_complete_in_vrf_read' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(vrf_read => { '' => 1, red => 0, blue => 1 }));
  my $job = run_arpnip(platform => $platform);
  is $job->status, 'done', 'arpnip done';
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 0, blue => 1 }, 'red incomplete, the others whole';
  ok scalar(grep { $_->{vrf} eq 'red' } @stored), 'entries read from red still stored';
  ok scalar(grep { $_->{vrf} eq 'blue' } @stored), 'blue stored';
};

sub not_whole_lines { return grep { m/not read whole/ } @informed }

subtest 'cli_arpnip__partial_read__info_line_names_vrfs_not_read_whole' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(vrf_read => { '' => 0, red => 0, blue => 1, gone => 1 }));
  run_arpnip(platform => $platform, settings => { vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:gone' } });
  is_deeply [ not_whole_lines() ],
    [ ' [192.0.2.1] arpnip (cli) - VRFs not read whole, so their entries are kept: "", "red"' ],
    'one info line naming the unread VRFs, the skipped VRF left out';
};

subtest 'cli_arpnip__whole_read__no_not_read_whole_line' => sub {
  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf()));
  is scalar(not_whole_lines()), 0, 'no line';
  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf(vrf_read => { '' => 1, red => 1, blue => 1, gone => 0 })),
    settings => { vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:gone' } });
  is scalar(not_whole_lines()), 0, 'no line when only a skipped VRF was read short';
};

subtest 'cli_arpnip__snmp_and_cli_both_read_vrf__complete_only_if_both_whole' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(
    vrf_read => { '' => 1, red => 1, blue => 0, green => 1 }, vrf_list_complete => 1));
  my $job = run_arpnip(platform => $platform, snmp => { snmp_fixture(red => 0) });
  is $job->status, 'done', 'arpnip done';
  is scalar(calls_of($platform, 'arpnip_by_vrf')), 1, 'the CLI worker ran after the SNMP one';
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 0, blue => 0, green => 1 },
    'red short on SNMP and blue short on CLI are both incomplete';
  is vars->{'vrf_list_complete'}, 1, 'both lists complete';
  is_deeply \@retired, [ [ { '' => 1, red => 0, blue => 0, green => 1 }, 1 ] ],
    'retire receives the merged vrf_read and list completeness';

  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf(vrf_list_complete => 0)),
    snmp => { snmp_fixture() });
  is vars->{'vrf_list_complete'}, 0, 'a short CLI list makes the merged list short';
  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf()),
    snmp => { snmp_fixture(list => 0) });
  is vars->{'vrf_list_complete'}, 0, 'a short SNMP list makes the merged list short';
};

subtest 'cli_arpnip__flattening_cli_with_per_vrf_snmp__vrf_read_from_snmp_only' => sub {
  my $platform = FlatPlatform->new(flat => [@flat]);
  my $job = run_arpnip(platform => $platform, snmp => { snmp_fixture(red => 0) });
  is $job->status, 'done', 'arpnip done';
  is scalar(calls_of($platform, 'arpnip')), 1, 'the flat CLI collector ran';
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 0, blue => 1 }, 'vrf_read as SNMP read it';
  is vars->{'vrf_list_complete'}, 1, 'vrf_list_complete as SNMP read it';
  is_deeply \@retired, [ [ { '' => 1, red => 0, blue => 1 }, 1 ] ], 'retire receives SNMP\'s reads';
};

subtest 'cli_arpnip__entries_in_vrf_missing_from_vrf_read__read_incomplete' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(vrf_read => { '' => 1, blue => 1 }));
  run_arpnip(platform => $platform);
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 0, blue => 1 }, 'red has entries, so it reads incomplete';
  ok scalar(grep { $_->{vrf} eq 'red' } @stored), 'red entries stored';
};

subtest 'cli_arpnip__empty_vrf_read_with_list_complete__no_vrf_vouched' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(entries => [], vrf_read => {}, vrf_list_complete => 1));
  my $job = run_arpnip(platform => $platform);
  is $job->status, 'done', 'arpnip done';
  ok !exists vars->{'vrf_read'}, 'no vrf_read, so nothing retires';
  is vars->{'vrf_list_complete'}, 0, 'a platform that read nothing cannot vouch for its list';
  run_arpnip(platform => $platform, snmp => { snmp_fixture() });
  is vars->{'vrf_list_complete'}, 0, 'nor make a complete SNMP list stand';
};

subtest 'cli_arpnip__default_and_empty_both_reported__complete_only_if_both' => sub {
  foreach my $pair ([1, 0], [0, 1]) {
    my $platform = ReportingPlatform->new(by_vrf => by_vrf(
      vrf_read => { '' => $pair->[0], default => $pair->[1], red => 1, blue => 1 }));
    run_arpnip(platform => $platform);
    is vars->{'vrf_read'}{''}, 0, "'' $pair->[0] and default $pair->[1] merge to 0";
    ok !exists vars->{'vrf_read'}{default}, 'no default key';
  }
};

subtest 'merge_vrf_reads__either_order__same_result' => sub {
  my $merge = \&App::Netdisco::Worker::Plugin::Arpnip::Nodes::merge_vrf_reads;
  my @sources = ([ { '' => 1, red => 0 }, 1, [4, 6] ], [ { red => 1, blue => 1 }, 0, [4, 6] ]);
  foreach my $order ([0, 1], [1, 0]) {
    delete @{ vars() }{qw/vrf_read vrf_read_families vrf_list_complete/};
    $merge->(@{ $sources[$_] }) for @$order;
    is_deeply vars->{'vrf_read'}, { '' => 1, red => 0, blue => 1 }, "vrf_read, order @$order";
    is vars->{'vrf_list_complete'}, 0, "vrf_list_complete, order @$order";
  }
};

# SNMP reads '', red and blue whole in both families; the CLI declares its own
subtest 'merge__v4_only_source_alone__vrf_not_whole' => sub {
  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf(families => [4])));
  is_deeply vars->{'vrf_read'}, { '' => 0, red => 0, blue => 0 }, 'no source read IPv6, so no VRF whole';
  is_deeply \@retired, [ [ { '' => 0, red => 0, blue => 0 }, 1 ] ], 'retire receives vrf => 0|1';
};

subtest 'merge__snmp_both_whole_and_v4_only_whole__vrf_whole' => sub {
  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf(families => [4])),
    snmp => { snmp_fixture() });
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 1, blue => 1 }, 'SNMP covers IPv6, both read IPv4 whole';
};

subtest 'merge__snmp_both_whole_and_v4_only_timeout__vrf_not_whole' => sub {
  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf(families => [4],
    vrf_read => { '' => 1, red => 0, blue => 1 })), snmp => { snmp_fixture() });
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 0, blue => 1 }, 'red IPv4 short on the CLI';
};

subtest 'merge__vrf_only_v4_only_source_listed__not_whole' => sub {
  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf(families => [4],
    vrf_read => { '' => 1, red => 1, blue => 1, green => 1 })), snmp => { snmp_fixture() });
  is vars->{'vrf_read'}{green}, 0, 'green: only an IPv4 source read it';
  is vars->{'vrf_read'}{red}, 1, 'red: SNMP read both families';
};

subtest 'merge__families_absent__treated_as_ipv4_only' => sub {
  my $result = by_vrf();
  delete $result->{families};
  run_arpnip(platform => ReportingPlatform->new(by_vrf => $result));
  is_deeply vars->{'vrf_read'}, { '' => 0, red => 0, blue => 0 }, 'alone, IPv6 is unvouched';
  run_arpnip(platform => ReportingPlatform->new(by_vrf => $result), snmp => { snmp_fixture() });
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 1, blue => 1 }, 'with SNMP reading both, whole';
  run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf(families => [4, 6])));
  is_deeply vars->{'vrf_read'}, { '' => 1, red => 1, blue => 1 }, 'declaring [4, 6] vouches both';
};

subtest 'merge__malformed_families__treated_as_ipv4_only' => sub {
  foreach my $families (undef, [], 4, 6, [5], [4, 7], [6, 'x'], 'six', { 4 => 1 }) {
    my $label = (ref $families ? ref($families) . ' ' . (join ',', map { $_ // 'undef' } (ref [] eq ref $families ? @$families : ())) : ($families // 'undef'));
    my $job = run_arpnip(platform => ReportingPlatform->new(by_vrf => by_vrf(families => $families)));
    is $job->status, 'done', "families $label: arpnip done";
    is_deeply vars->{'vrf_read'}, { '' => 0, red => 0, blue => 0 }, "families $label: read as IPv4 only";
  }
};

subtest 'cli_arpnip__session_fails__defers_and_vrf_read_untouched' => sub {
  my $job = run_arpnip(platform => undef);
  is $job->status, 'defer', 'no session defers as today';
  ok !exists vars->{'vrf_read'}, 'no vrf_read';

  foreach my $case ([ 'undef return', ReportingPlatform->new(by_vrf => undef) ],
                    [ 'die', ReportingPlatform->new(die => "channel closed\n") ]) {
    my ($label, $platform) = @$case;
    $job = run_arpnip(platform => $platform);
    is $job->status, 'defer', "$label defers";
    like $job->log, ($label eq 'die' ? qr/channel closed/ : qr/no ARP data/), "$label reason in the job log";
    ok !exists vars->{'vrf_read'}, "$label leaves no vrf_read";
    ok !exists vars->{'vrf_list_complete'}, "$label leaves no vrf_list_complete";

    $job = run_arpnip(platform => $platform, snmp => { snmp_fixture(red => 0) });
    is_deeply vars->{'vrf_read'}, { '' => 1, red => 0, blue => 1 }, "$label leaves SNMP's vrf_read as read";
    is vars->{'vrf_list_complete'}, 1, "$label leaves SNMP's vrf_list_complete as read";
    ok scalar(grep { $_->status eq 'defer' and $_->phase eq 'main' } @{ $job->_statuslist }),
      "$label records a defer from the CLI worker";
  }
};

# the SNMP fixture reports 10.40.0.5 / 00:11:22:33:44:07 in red; a flattening CLI
# collector then reports hosts with no VRF
sub merge_run {
  my ($flat, %settings) = @_;
  return run_arpnip(platform => FlatPlatform->new(flat => $flat),
    snmp => { snmp_fixture() }, settings => \%settings);
}

subtest 'merge__switch_on__flattened_copy_of_named_entry_dropped' => sub {
  merge_run([ { ip => '10.40.0.5', mac => '00:11:22:33:44:07' } ]);
  is entries(), '10.40.0.5|00:11:22:33:44:07|red', 'only the red entry remains';
  is scalar(grep { m/dropped 1 flattened/ } @logged), 1, 'one debug line with the count';
};

# A whole SNMP default read is the device's own word that the host is in the
# default table, so a twin there is a genuine second binding (M-1). Only a
# flattening collector or a default read that stayed partial (on Juniper, rows
# of virtual routers mixed in) is untrusted.
sub snmp_with_default_twin {
  my ($default_complete) = @_;
  my %snmp = snmp_fixture();
  $snmp{vrf}{default} = { complete => $default_complete,
    neighbors => { '7.10.40.0.5' => { ip => '10.40.0.5', mac => '00:11:22:33:44:07' } } };
  return \%snmp;
}

subtest 'merge__whole_snmp_default_read__genuine_twin_kept' => sub {
  run_arpnip(snmp => snmp_with_default_twin(1));
  is entries(), join(' ', sort '10.40.0.5|00:11:22:33:44:07|red', '10.40.0.5|00:11:22:33:44:07|'),
    'the default-table entry and the red entry are both stored';
  is scalar(grep { m/dropped \d+ flattened/ } @logged), 0, 'no drop line';
};

subtest 'merge__partial_snmp_default_read__twin_dropped' => sub {
  run_arpnip(snmp => snmp_with_default_twin(0));
  is entries(), '10.40.0.5|00:11:22:33:44:07|red', 'only the red entry remains';
  is scalar(grep { m/dropped 1 flattened/ } @logged), 1, 'one debug line with the count';
};

# IOS XR's global show ipv6 neighbors also lists every VRF's neighbors, so
# the platform tags those entries mixed though the read was whole
subtest 'cli_arpnip__global_table_lists_a_vrf_host__default_copy_dropped' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(entries => [
    { ip => '2001:db8:60::2', mac => '02:00:00:00:06:01', vrf => '', mixed => 1 },
    { ip => '2001:db8:60::2', mac => '02:00:00:00:06:01', vrf => 'red' },
    { ip => '192.0.2.10', mac => '00:11:22:33:44:01', vrf => '' },
  ]));
  run_arpnip(platform => $platform);
  is entries(), join(' ', sort '2001:db8:60::2|02:00:00:00:06:01|red', '192.0.2.10|00:11:22:33:44:01|'),
    'the default-table copy of the red host is dropped, the default host kept';
};

# a whole, untagged global read is the device's own word, as on the SNMP path
subtest 'cli_arpnip__whole_global_read_twin_untagged__both_kept' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(entries => [
    { ip => '10.40.0.5', mac => '00:11:22:33:44:07', vrf => '' },
    { ip => '10.40.0.5', mac => '00:11:22:33:44:07', vrf => 'red' },
  ]));
  run_arpnip(platform => $platform);
  is entries(), join(' ', sort '10.40.0.5|00:11:22:33:44:07|red', '10.40.0.5|00:11:22:33:44:07|'),
    'the default-table entry and the red entry are both stored';
  is scalar(grep { m/dropped \d+ flattened/ } @logged), 0, 'no drop line';
};

subtest 'cli_arpnip__partial_global_read_twin__default_copy_dropped' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(
    vrf_read => { '' => 0, red => 1, blue => 1 },
    entries => [
      { ip => '10.40.0.5', mac => '00:11:22:33:44:07', vrf => '' },
      { ip => '10.40.0.5', mac => '00:11:22:33:44:07', vrf => 'red' },
    ]));
  run_arpnip(platform => $platform);
  is entries(), '10.40.0.5|00:11:22:33:44:07|red', 'only the red entry remains';
};

subtest 'cli_arpnip__mixed_tag__not_passed_to_store_arp' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(entries => [
    { ip => '2001:db8::10', mac => '00:11:22:33:44:02', vrf => '', mixed => 1 },
  ]));
  run_arpnip(platform => $platform);
  is scalar(@stored), 1, 'the entry is stored';
  ok !exists $stored[0]{mixed}, 'without the mixed tag';
};

subtest 'cli_arpnip__whole_snmp_default_entry_and_cli_global_copy__snmp_entry_wins' => sub {
  my $platform = ReportingPlatform->new(by_vrf => by_vrf(entries => [
    { ip => '10.40.0.5', mac => '00:11:22:33:44:07', vrf => '' },
    { ip => '10.40.0.5', mac => '00:11:22:33:44:07', vrf => 'red' },
  ]));
  run_arpnip(platform => $platform, snmp => snmp_with_default_twin(1));
  is entries(), join(' ', sort '10.40.0.5|00:11:22:33:44:07|red', '10.40.0.5|00:11:22:33:44:07|'),
    'the whole SNMP default read still vouches for its genuine twin';
};

subtest 'merge__whole_snmp_default_entry_and_cli_flat_copy__snmp_entry_wins' => sub {
  # the CLI driver runs after SNMP and its flat copy has the same cache key
  run_arpnip(platform => FlatPlatform->new(flat => [ { ip => '10.40.0.5', mac => '00:11:22:33:44:07' } ]),
    snmp => snmp_with_default_twin(1));
  is entries(), join(' ', sort '10.40.0.5|00:11:22:33:44:07|red', '10.40.0.5|00:11:22:33:44:07|'),
    'the default-table entry from the whole SNMP read is kept beside red';
};

subtest 'merge__flattened_tag__not_passed_to_store_arp' => sub {
  my $snmp = snmp_with_default_twin(0);
  $snmp->{vrf}{default}{neighbors}{'7.10.40.0.9'} = { ip => '10.40.0.9', mac => '00:11:22:33:44:09' };
  run_arpnip(snmp => $snmp);
  my ($partial) = grep { $_->{ip} eq '10.40.0.9' } @stored;
  ok $partial, 'an untwinned entry of a partial default read is stored';
  ok !exists $partial->{flattened}, 'without the tag';
  merge_run([ { ip => '192.0.2.10', mac => '00:11:22:33:44:01' } ]);
  my ($flat) = grep { $_->{ip} eq '192.0.2.10' } @stored;
  ok $flat, 'an untwinned CLI flat entry is stored';
  ok !exists $flat->{flattened}, 'without the tag';
};

subtest 'merge__switch_off__nothing_dropped' => sub {
  # a flat-path platform may hand back vrf keys; the switch alone decides
  my @pair = ({ ip => '10.40.0.5', mac => '00:11:22:33:44:07', vrf => 'red' },
              { ip => '10.40.0.5', mac => '00:11:22:33:44:07' });
  foreach my $settings ({ store_vrfs => 0 }, { skip_vrf_devices => ['192.0.2.1'] }) {
    run_arpnip(platform => FlatPlatform->new(flat => [ map { { %$_ } } @pair ]), settings => $settings);
    is scalar(grep { m/dropped \d+ flattened/ } @logged), 0, 'no drop line';
    is entries(), join(' ', sort '10.40.0.5|00:11:22:33:44:07|red', '10.40.0.5|00:11:22:33:44:07|-'),
      'named entry and its empty-vrf twin both survive';
  }
};

subtest 'merge__flattened_entry_with_no_named_twin__kept' => sub {
  merge_run([ { ip => '192.0.2.10', mac => '00:11:22:33:44:01' } ]);
  is entries(), join(' ', sort '10.40.0.5|00:11:22:33:44:07|red', '192.0.2.10|00:11:22:33:44:01|-'),
    'unrelated flat entry kept';
  is scalar(grep { m/dropped \d+ flattened/ } @logged), 0, 'no drop line';
};

subtest 'merge__dotted_and_colon_mac_forms__treated_as_one_host' => sub {
  merge_run([ { ip => '10.40.0.5', mac => '0011.2233.4407' } ]);
  is entries(), '10.40.0.5|00:11:22:33:44:07|red', 'dotted flat copy dropped';
};

subtest 'merge__same_ip_different_mac__kept' => sub {
  merge_run([ { ip => '10.40.0.5', mac => '00:11:22:33:44:99' } ]);
  is scalar(grep { $_->{ip} eq '10.40.0.5' } @stored), 2, 'a different host on the same IP is kept';
};

subtest 'merge__same_mac_different_ip__kept' => sub {
  merge_run([ { ip => '10.40.0.6', mac => '00:11:22:33:44:07' } ]);
  is scalar(grep { $_->{mac} eq '00:11:22:33:44:07' } @stored), 2, 'one MAC with two IPs keeps both';
};

subtest 'merge__node_key_instead_of_mac__treated_as_one_host' => sub {
  merge_run([ { ip => '10.40.0.5', node => '00:11:22:33:44:07' } ]);
  is entries(), '10.40.0.5|00:11:22:33:44:07|red', 'flat copy keyed by node dropped';
};

subtest 'merge__ipv6_short_and_long_forms__treated_as_one_address' => sub {
  my %snmp = snmp_fixture();
  $snmp{vrf}{red}{neighbors} = { v6 => { ip => '2001:db8::5', mac => '00:11:22:33:44:07' } };
  run_arpnip(platform => FlatPlatform->new(flat => [
      { ip => '2001:0db8:0000:0000:0000:0000:0000:0005', mac => '00:11:22:33:44:07' } ]),
    snmp => \%snmp);
  is scalar(@stored), 1, 'long-form flat copy dropped';
  is $stored[0]{vrf}, 'red', 'the named entry remains';
};

subtest 'merge__unparsable_named_entry_before_valid_one__valid_twin_still_dropped' => sub {
  my $drop = \&App::Netdisco::Worker::Plugin::Arpnip::Nodes::drop_flattened_twins;
  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  vars->{'arps'} = [
    { ip => '10.40.0.9', mac => 'not-a-mac', vrf => 'red' },
    { ip => '10.40.0.5', mac => '00:11:22:33:44:07', vrf => 'red' },
    { ip => '10.40.0.5', mac => '00:11:22:33:44:07', flattened => 1 },
  ];
  $drop->($device);
  is scalar(@{ vars->{'arps'} }), 2, 'the flat twin of the valid named entry is dropped';
  is_deeply [ map { $_->{vrf} // '-' } @{ vars->{'arps'} } ], [ 'red', 'red' ], 'both named entries remain';
};

done_testing;
