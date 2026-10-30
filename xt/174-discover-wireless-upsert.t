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
use App::Netdisco::Worker::Plugin::Discover::Wireless ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The Wireless worker runs for real with SNMP stubbed. upsert and remove_unseen
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

package FakeSNMP;
our $AUTOLOAD;
sub new { my ($class, %vals) = @_; return bless { walk_failures => [], %vals }, $class; }
sub walk_failures { $_[0]{walk_failures} }
sub walk_status { $_[0]{walk_status}{$_[1]} }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  # a failing walk records itself on its first read only, as a cached table does
  if (my $failure = delete $self->{fail_on_read}{$method}) {
    push @{ $self->{walk_failures} }, $failure;
    $self->{walk_status}{$method} = $failure;
  }
  # SNMP::Info returns an empty list, not undef, for a method the device does
  # not support, so a caller in list context sees no value at all
  return unless exists $self->{$method};
  return $self->{$method};
}

package FakeRows;
sub new { my ($class, @rows) = @_; return bless { rows => [@rows] }, $class; }
sub all { return @{ $_[0]->{rows}} }
sub search { return $_[0] }

package FakePort;
sub port { return $_[0]{port} }

package FakeSchema;
sub txn_do { my ($self, $code, @args) = @_; return $code->(@args) }
sub resultset { return App::Netdisco::DB->resultset($_[1]) }

package main;

my %device_cols = (
  ip => '192.0.2.1', uptime => 900, description => 'desc', name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', snmp_class => 'SNMP::Info::Layer2',
  custom_fields => '{}', snmp_ver => 2,
);

my %base_snmp = (
  interfaces      => { 1 => 'wlan0', 2 => 'wlan1', 3 => 'wlan1' },
  i_ssidlist      => { '1.1' => 'guest', '1.2' => 'corp', '2.1' => 'lab' },
  i_ssidbcast     => { '1.1' => 'true', '1.2' => 'false', '2.1' => 'true' },
  i_ssidmac       => { '1.1' => 'aa:00:00:00:00:01', '1.2' => 'aa:00:00:00:00:02',
                       '2.1' => 'aa:00:00:00:00:03' },
  i_80211channel  => { 1 => 6, 2 => 11 },
  dot11_cur_tx_pwr_mw => { 1 => 20, 2 => 100 },
);

sub outcome {
  my ($method) = @_;
  return { method => $method, leaf => "MIB::$method", reason => 'timeout',
           rows => 1, walk => 'bulkwalk', complete => 0 };
}

my (@upserts, @removals, @warnings, @port_reads);

sub run_wireless {
  my (%snmp) = @_;
  delete @{ vars() }{qw/device_changed new_device device_ports hook_data timestamp incomplete_walks/};
  @upserts = @removals = @warnings = @port_reads = ();

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{_column_data}{since_last_discover} = 0;

  my $fake_snmp = FakeSNMP->new(%base_snmp, %snmp);
  no warnings 'once';

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::Wireless::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::Wireless::warning
    = sub { push @warnings, @_ };
  local *App::Netdisco::DB::Result::Device::ports
    = sub { return FakeRows->new(map { bless { port => $_ }, 'FakePort' } 'wlan0', 'wlan1') };
  local *App::Netdisco::DB::Result::Device::ssids
    = sub { push @port_reads, 'ssids'; return FakeRows->new };
  local *App::Netdisco::DB::Result::Device::wireless_ports
    = sub { push @port_reads, 'wireless_ports'; return FakeRows->new };
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
    job => 0, device => $device, action => 'discover::wireless',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

sub status_messages { return join "\n", map { $_->log } @{ $_[0]->_statuslist } }

sub ssid_upserts { return grep { $_->[0] eq 'DevicePortSsid' } @upserts }
sub ssid_removals { return grep { $_->[0] eq 'DevicePortSsid' } @removals }
sub chan_upserts { return grep { $_->[0] eq 'DevicePortWireless' } @upserts }
sub chan_removals { return grep { $_->[0] eq 'DevicePortWireless' } @removals }

subtest 'wireless__normal_run__upserts_both_tables_and_removes_unseen' => sub {
  my $job = run_wireless();
  my @ssids = ssid_upserts();
  is scalar @ssids, 1, 'one SSID upsert';
  is_deeply $ssids[0][1], [
    { ip => '192.0.2.1', port => 'wlan0', ssid => 'guest', broadcast => 'true', bssid => 'aa:00:00:00:00:01' },
    { ip => '192.0.2.1', port => 'wlan0', ssid => 'corp', broadcast => 'false', bssid => 'aa:00:00:00:00:02' },
    { ip => '192.0.2.1', port => 'wlan1', ssid => 'lab', broadcast => 'true', bssid => 'aa:00:00:00:00:03' },
  ], 'uniform SSID rows';
  my @chans = chan_upserts();
  is scalar @chans, 1, 'one channel upsert';
  is_deeply $chans[0][1], [
    { ip => '192.0.2.1', port => 'wlan0', channel => 6, power => 20 },
    { ip => '192.0.2.1', port => 'wlan1', channel => 11, power => 100 },
  ], 'uniform channel rows';
  my @sr = ssid_removals();
  is_deeply $sr[0][1], { ip => '192.0.2.1' };
  is_deeply $sr[0][2], [ { port => 'wlan0', bssid => 'aa:00:00:00:00:01' },
    { port => 'wlan0', bssid => 'aa:00:00:00:00:02' },
    { port => 'wlan1', bssid => 'aa:00:00:00:00:03' } ];
  my @cr = chan_removals();
  is_deeply $cr[0][1], { ip => '192.0.2.1' };
  is_deeply $cr[0][2], [ { port => 'wlan0' }, { port => 'wlan1' } ];
  is scalar @port_reads, 0, 'no delete and populate through relationships';
  is scalar @warnings, 0, 'no warning';
  like status_messages($job), qr/added 3 new SSIDs, added 2 new wireless channels/;
};

subtest 'wireless__two_ifindexes_one_port__one_row_same_winner' => sub {
  my @runs;
  foreach my $order (1, 2) {
    # same data, different hash insertion order, as perl hash order varies by run
    my %channel = $order == 1 ? (2 => 11, 3 => 36, 1 => 6) : (3 => 36, 1 => 6, 2 => 11);
    my %mac = $order == 1
      ? ('2.1' => 'aa:00:00:00:00:03', '2.2' => 'aa:00:00:00:00:03', '1.1' => 'aa:00:00:00:00:01')
      : ('1.1' => 'aa:00:00:00:00:01', '2.2' => 'aa:00:00:00:00:03', '2.1' => 'aa:00:00:00:00:03');
    my %list = $order == 1
      ? ('2.2' => 'second', '2.1' => 'first', '1.1' => 'guest')
      : ('1.1' => 'guest', '2.1' => 'first', '2.2' => 'second');
    run_wireless(i_80211channel => \%channel, i_ssidlist => \%list, i_ssidmac => \%mac,
      dot11_cur_tx_pwr_mw => { 1 => 20, 2 => 100, 3 => 200 });
    push @runs, [ (chan_upserts())[0][1], (ssid_upserts())[0][1] ];
  }
  is_deeply $runs[0], $runs[1], 'same rows both runs';
  is scalar @{ $runs[0][0] }, 2, 'one channel row per port';
  is $runs[0][0][1]{channel}, 11, 'lowest ifIndex wins the channel';
  is scalar @{ $runs[0][1] }, 2, 'one SSID row per port and bssid';
  is $runs[0][1][1]{ssid}, 'first', 'lowest entry wins the SSID';
};

subtest 'wireless__controller_radio_keys__channels_by_oid_without_warnings' => sub {
  # a controller such as Airespace keys its radios by AP MAC and slot
  my %interfaces = ('0.11.133.1.2.3.0' => 'wlan0', '0.11.133.1.2.3.1' => 'wlan1',
                    '0.11.133.1.2.10.0' => 'wlan1');
  my @perl_warnings;
  local $SIG{__WARN__} = sub { push @perl_warnings, @_ };
  run_wireless(
    interfaces => \%interfaces,
    i_ssidlist => { '0.11.133.1.2.3.0.1' => 'guest' },
    i_ssidbcast => { '0.11.133.1.2.3.0.1' => 'true' },
    i_ssidmac => { '0.11.133.1.2.3.0.1' => 'aa:00:00:00:00:01' },
    i_80211channel => { '0.11.133.1.2.10.0' => 36, '0.11.133.1.2.3.1' => 11,
                        '0.11.133.1.2.3.0' => 6 },
    dot11_cur_tx_pwr_mw => {},
  );
  is_deeply [ map {"$_->{port}:$_->{channel}"} @{ (chan_upserts())[0][1] || [] } ],
    [ 'wlan0:6', 'wlan1:11' ], 'lowest radio key wins the channel';
  is_deeply \@perl_warnings, [], 'no perl warnings';
};

subtest 'wireless__no_ssids_complete_walk__removes_both_tables_rows' => sub {
  my $job = run_wireless(i_ssidlist => {});
  is scalar @upserts, 0, 'no upsert';
  my @sr = ssid_removals();
  my @cr = chan_removals();
  is scalar @sr, 1, 'one SSID removal';
  is scalar @cr, 1, 'one channel removal';
  is_deeply $sr[0][2], [], 'every SSID row goes';
  is_deeply $cr[0][2], [], 'every channel row goes';
  is scalar @warnings, 0, 'no warning';
};

subtest 'wireless__incomplete_i_ssidlist__keeps_both_tables' => sub {
  my $job = run_wireless(i_ssidlist => undef,
    fail_on_read => { i_ssidlist => outcome('i_ssidlist') });
  is scalar @upserts, 0, 'no upsert';
  is scalar @removals, 0, 'no removal';
  like status_messages($job), qr/device_port_ssid - kept existing rows.*i_ssidlist /;
  like status_messages($job), qr/device_port_wireless - kept existing rows.*i_ssidlist /;
  ok !$job->is_cancelled, 'the guard skips and never cancels';
};

for my $method (qw/i_ssidbcast i_ssidmac/) {
  subtest "wireless__incomplete_${method}__keeps_ssids_writes_channels" => sub {
    my $job = run_wireless(fail_on_read => { $method => outcome($method) });
    is scalar(ssid_upserts()), 0, 'no SSID upsert';
    is scalar(ssid_removals()), 0, 'no SSID removal';
    is scalar(chan_upserts()), 1, 'channels written';
    is scalar(chan_removals()), 1, 'channels pruned';
    like status_messages($job), qr/device_port_ssid - kept existing rows.*\Q$method\E /;
  };
}

for my $method (qw/i_80211channel dot11_cur_tx_pwr_mw/) {
  subtest "wireless__incomplete_${method}__keeps_channels_writes_ssids" => sub {
    my $job = run_wireless(fail_on_read => { $method => outcome($method) });
    is scalar(chan_upserts()), 0, 'no channel upsert';
    is scalar(chan_removals()), 0, 'no channel removal';
    is scalar(ssid_upserts()), 1, 'SSIDs written';
    is scalar(ssid_removals()), 1, 'SSIDs pruned';
    like status_messages($job), qr/device_port_wireless - kept existing rows.*\Q$method\E /;
    ok !$job->is_cancelled, 'the guard skips and never cancels';
  };
}

subtest 'wireless__incomplete_interfaces__keeps_both_tables' => sub {
  my $job = run_wireless(fail_on_read => { interfaces => outcome('interfaces') });
  is scalar @upserts, 0, 'no upsert';
  is scalar @removals, 0, 'no removal';
};

subtest 'wireless__absent_channel_walk__keeps_channels_and_errors_the_job' => sub {
  my $job = run_wireless(walk_status => { i_80211channel =>
    { %{ outcome('i_80211channel') }, reason => 'absent', complete => 1, rows => 0 } });
  is scalar(chan_removals()), 0, 'channels kept';
  is scalar(ssid_upserts()), 1, 'SSIDs written';
  my @errors = map { $_->log } grep { $_->status eq 'error' } @{ $job->_statuslist };
  is scalar @errors, 1, 'one error status';
  like $errors[0], qr/netdisco-mibs/;
};

subtest 'wireless__ignored_port_in_device_ports__rows_skipped' => sub {
  run_wireless(interfaces => { 1 => 'wlan0', 2 => 'gone0', 3 => 'wlan1' });
  is_deeply [ map { $_->{port} } @{ (ssid_upserts())[0][1] } ], [ 'wlan0', 'wlan0' ];
  is_deeply [ map { $_->{port} } @{ (chan_upserts())[0][1] } ], [ 'wlan0' ];
};

done_testing;
