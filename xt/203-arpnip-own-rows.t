#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Backend::Job;
use App::Netdisco::Transport::SSH ();
use App::Netdisco::Worker::Plugin::Arpnip::Nodes ();

use NetAddr::IP::Lite ':lower';
use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# With store_vrfs on the store phase drops a router's own rows from every
# driver, since a CLI collector reports them and SNMP::Info's reader does not.
# The two own-identity queries are faked, so these tests need no database.

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

my $drop = \&App::Netdisco::Worker::Plugin::Arpnip::Nodes::drop_own_entries;

my %device_cols = (
  ip => '192.0.2.1', name => 'router1', layers => '00000100', snmp_ver => 2,
  snmp_class => 'SNMP::Info::Layer3',
);

our $queries = 0;
our @logged;

# own and port MACs are as_ieee strings; own addresses are [vrf, address] pairs
sub fake_identity {
  my %own = @_;
  my %macs = map { ($_ => 1) } @{ $own{macs} || [] };
  my %ports = map { ($_ => 1) } @{ $own{port_macs} || [] };
  my %addresses = map { my ($vrf, $addr) = @$_; (join(chr(28), $vrf, NetAddr::IP::Lite->new($addr)->addr) => 1) } @{ $own{addresses} || [] };
  return sub { ++$queries; return (\%macs, \%ports, \%addresses) };
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

sub new_device { App::Netdisco::DB->resultset('Device')->new_result({ %device_cols }) }
sub left { return join ' ', map { join '|', $_->{ip}, $_->{vrf} // '-' } @{ vars->{'arps'} } }

sub drop_with {
  my ($identity, $entries, %settings) = @_;
  $queries = 0; @logged = ();
  vars->{'arps'} = $entries;
  vars->{'vrf_read'} = ($settings{no_read} ? undef : { '' => 1 });
  delete vars->{'vrf_read'} if $settings{no_read};
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::own_identity = $identity;
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::debug = sub { push @logged, join '', @_ };
  $drop->(new_device());
}

subtest 'drop_own_entries__switch_on__entry_at_port_mac_dropped' => sub {
  drop_with(fake_identity(macs => ['00:aa:bb:cc:dd:01']), [
    { ip => '10.40.0.77', mac => '0000.aabb.ccdd', vrf => 'red' },
    { ip => '10.40.0.78', mac => '00aa.bbcc.dd01', vrf => 'red' },
    { ip => '10.40.0.79', node => '00:AA:BB:CC:DD:01', vrf => '' },
  ]);
  is left(), '10.40.0.77|red', 'dotted and node-keyed forms of the port MAC dropped';
  is scalar(grep { m/dropped 2 ARP entries/ } @logged), 1, 'one debug line with the count';
  is $queries, 1, 'identity fetched once';
};

subtest 'drop_own_entries__switch_on__entry_at_own_address_in_same_vrf_dropped' => sub {
  drop_with(fake_identity(port_macs => ['00:11:22:33:44:01', '00:11:22:33:44:02'],
      addresses => [ ['red', '10.40.0.1'], ['', '172.20.20.14'] ]), [
    { ip => '10.40.0.1',    mac => '00:11:22:33:44:01', vrf => 'red' },
    { ip => '172.20.20.14', mac => '00:11:22:33:44:02', vrf => '' },
    { ip => '172.20.20.14', mac => '00:11:22:33:44:03' },
  ]);
  is left(), '172.20.20.14|-', 'own addresses at a port MAC dropped, vrf absent read as the global table; the unknown MAC kept';
};

subtest 'drop_own_entries__own_address_in_other_vrf__kept' => sub {
  drop_with(fake_identity(port_macs => ['00:11:22:33:44:99'], addresses => [ ['red', '10.40.0.1'] ]), [
    { ip => '10.40.0.1', mac => '00:11:22:33:44:99', vrf => 'blue' },
  ]);
  is left(), '10.40.0.1|blue', 'a host in blue at the address the device holds in red is kept';
  is scalar(@logged), 0, 'no drop line';
};

subtest 'drop_own_entries__shared_own_address_in_two_vrfs__both_dropped' => sub {
  drop_with(fake_identity(port_macs => ['00:11:22:33:44:01', '00:11:22:33:44:02', '00:11:22:33:44:03'],
      addresses => [ ['red', '10.40.0.1'], ['blue', '10.40.0.1'] ]), [
    { ip => '10.40.0.1', mac => '00:11:22:33:44:01', vrf => 'red' },
    { ip => '10.40.0.1', mac => '00:11:22:33:44:02', vrf => 'blue' },
    { ip => '10.40.0.1', mac => '00:11:22:33:44:03', vrf => 'green' },
  ]);
  is left(), '10.40.0.1|green', 'red and blue dropped, green kept';
};

subtest 'drop_own_entries__ipv6_long_form__matches_short_form' => sub {
  drop_with(fake_identity(port_macs => ['00:11:22:33:44:01'], addresses => [ ['', '2001:db8::1'] ]), [
    { ip => '2001:0db8:0000:0000:0000:0000:0000:0001', mac => '00:11:22:33:44:01', vrf => '' },
  ]);
  is left(), '', 'dropped';
};

subtest 'drop_own_entries__host_entries__kept' => sub {
  drop_with(fake_identity(macs => ['00:aa:bb:cc:dd:01'], addresses => [ ['red', '10.40.0.1'] ]), [
    { ip => '10.40.0.5', mac => '00:11:22:33:44:07', vrf => 'red' },
    { ip => 'garbage',   mac => 'not-a-mac',         vrf => 'red' },
  ]);
  is left(), '10.40.0.5|red garbage|red', 'hosts and unparsable rows untouched';
};

subtest 'drop_own_entries__host_at_mac_of_port_without_device_address__kept' => sub {
  # Aruba lists each AP's Ethernet MAC as a port; the AP is a host
  drop_with(fake_identity(macs => ['00:aa:bb:cc:dd:01'], port_macs => ['00:aa:bb:cc:dd:01', '00:ab:00:00:00:31']), [
    { ip => '10.20.0.31', mac => '00:ab:00:00:00:31', vrf => '' },
  ]);
  is left(), '10.20.0.31|', 'kept';
  drop_with(fake_identity(macs => ['00:aa:bb:cc:dd:01'], port_macs => ['00:aa:bb:cc:dd:01', '00:ab:00:00:00:31']), [
    { ip => '10.20.0.31', mac => '00:ab:00:00:00:31', vrf => '' },
  ]);
  is left(), '10.20.0.31|', 'kept when the MAC is only a port MAC with no address';
};

subtest 'drop_own_entries__stale_own_alias_at_host_mac__kept' => sub {
  drop_with(fake_identity(macs => ['00:aa:bb:cc:dd:01'], port_macs => ['00:aa:bb:cc:dd:01'],
      addresses => [ ['red', '10.40.0.254'] ]), [
    { ip => '10.40.0.254', mac => '00:11:22:33:44:77', vrf => 'red' },
  ]);
  is left(), '10.40.0.254|red', 'a host at a removed alias is kept';
};

subtest 'drop_own_entries__no_vrf_read__nothing_dropped' => sub {
  my @own = ({ ip => '10.40.0.1', mac => '00:aa:bb:cc:dd:01', vrf => 'red' });
  my $identity = fake_identity(macs => ['00:aa:bb:cc:dd:01']);
  drop_with($identity, [ map { { %$_ } } @own ], no_read => 1);
  is left(), '10.40.0.1|red', 'vrf_read absent, own rows kept';
  is $queries, 0, 'no query';
  drop_with($identity, [ map { { %$_ } } @own ], no_read => 1);
  vars->{'vrf_read'} = {};
  $queries = 0;
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::own_identity = $identity;
  $drop->(new_device());
  is left(), '10.40.0.1|red', 'empty vrf_read, own rows kept';
  is $queries, 0, 'no query';
};

# own_identity through a fake schema: key formats must agree with drop_own_entries
{
  package FakeRs;
  sub new { bless { rows => $_[1] }, $_[0] }
  sub search { $_[0] }
  sub hri { $_[0] }
  sub all { @{ $_[0]{rows} } }
  package FakeSchema;
  sub new { bless { %{ $_[1] } }, $_[0] }
  sub resultset { FakeRs->new($_[0]{ $_[1] }) }
}

subtest 'own_identity__mixed_forms__normalized_keys' => sub {
  my $schema = FakeSchema->new({
    DeviceIp => [
      { alias => '10.40.0.1/32', vrf => 'red', port => 'Vlan40' },
      { alias => '2001:0DB8::1', vrf => '',    port => 'Vlan40' },
      { alias => '10.9.9.9',     vrf => undef, port => undef },
      { alias => 'junk',         vrf => '',    port => 'Vlan40' },
    ],
    DevicePort => [
      { port => 'Vlan40', mac => '00AA.BBCC.DD01' },
      { port => 'ap1',    mac => '00:AB:00:00:00:31' },
      { port => 'lo0',    mac => '00:00:00:00:00:00' },
    ],
  });
  my $device = new_device();
  $device->{'_column_data'}{mac} = undef;
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::schema = sub { $schema };
  my ($own, $ports, $addresses) = App::Netdisco::Worker::Plugin::Arpnip::Nodes::own_identity($device);
  is_deeply $own, { '00:aa:bb:cc:dd:01' => 1 }, 'own MACs: the address-holding port only, undef device mac skipped';
  is_deeply $ports, { '00:aa:bb:cc:dd:01' => 1, '00:ab:00:00:00:31' => 1 }, 'port MACs normalized, zero MAC excluded';
  is_deeply $addresses, { join(chr(28), 'red', '10.40.0.1') => 1, join(chr(28), '', '2001:db8:0:0:0:0:0:1') => 1,
    join(chr(28), '', '10.9.9.9') => 1 }, 'addresses keyed by vrf and normalized address';

  $device->{'_column_data'}{mac} = '00:AA:BB:00:00:09';
  ($own) = App::Netdisco::Worker::Plugin::Arpnip::Nodes::own_identity($device);
  ok $own->{'00:aa:bb:00:00:09'}, 'device mac included, lower-cased';
};

# store phase through the Runner, with a CLI-style entry set
sub run_store {
  my (%settings) = @_;
  my $platform_class = delete($settings{platform}) // 'CliPlatform';
  no warnings 'once';
  delete @{ vars() }{qw/arps timestamp hook_data/};
  my @stored;
  $queries = 0;
  my $device = new_device();
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_arpnip'} = 0;
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::own_identity =
    fake_identity(macs => ['00:aa:bb:cc:dd:01'], port_macs => ['00:aa:bb:cc:dd:01', '00:11:22:33:44:01', '00:11:22:33:44:02'],
      addresses => [ ['red', '10.40.0.1'], ['', '172.20.20.14'] ]);
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::store_arp = sub { push @stored, { %{ $_[0] } } };
  # device_vrf writes need a database; xt/209 covers record_cli_vrfs
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::record_cli_vrfs = sub { 0 };
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::retire_unvouched_arps = sub { 0 };
  local *App::Netdisco::DB::Result::Device::update = sub { return $_[0] };
  local *App::Netdisco::Transport::SSH::session_for = sub { return MySession->new(platform => $platform_class->new, host => '192.0.2.1', ssh => 'SSH', auth => { platform => 'Stub' }) };

  my $job = App::Netdisco::Backend::Job->new({ job => 0, device => $device, action => 'arpnip::nodes' });
  with_settings(sub {
    try { MyWorker->new()->run($job) }
    catch { $job->status('error'); $job->log("error running job: $_") };
  }, device_auth => [{ driver => 'cli' }], store_vrfs => 1, %settings);
  return ($job, \@stored);
}

{
  package CliPlatform;
  sub new { bless {}, shift }
  # IOS-style: the router's own `-` age rows come back with the hosts
  sub arpnip_by_vrf {
    return { entries => [ arpnip() ], vrf_read => { red => 1, blue => 1, '' => 1 },
             vrf_list_complete => 1, families => [4, 6] };
  }
  sub arpnip {
    return (
      { ip => '10.40.0.1',    mac => '00:11:22:33:44:01', vrf => 'red' },
      { ip => '10.40.0.5',    mac => '00:11:22:33:44:07', vrf => 'red' },
      { ip => '172.20.20.14', mac => '00:11:22:33:44:02', vrf => '' },
      { ip => '10.41.0.9',    mac => '00:aa:bb:cc:dd:01', vrf => 'blue' },
    );
  }
}


{
  package FlatCliPlatform;
  sub new { bless {}, shift }
  sub arpnip { return CliPlatform::arpnip() }
}

subtest 'store_phase__cli_entry_set_switch_on__own_rows_not_stored' => sub {
  my ($job, $stored) = run_store();
  is $job->status, 'done', 'arpnip done';
  is join(' ', map { "$_->{ip}|$_->{vrf}" } @$stored), '10.40.0.5|red', 'only the host stored';
  is $queries, 1, 'one identity fetch for the job';
};

subtest 'store_phase__flat_collector_no_vrf_read__own_rows_kept' => sub {
  my ($job, $stored) = run_store(platform => 'FlatCliPlatform');
  is $job->status, 'done', 'arpnip done';
  is scalar(@$stored), 4, 'no VRF read, so nothing dropped';
  is $queries, 0, 'no identity query';
};

subtest 'drop_own_entries__switch_off__nothing_dropped_no_query' => sub {
  my ($job, $stored) = run_store(store_vrfs => 0);
  is $job->status, 'done', 'arpnip done';
  is scalar(@$stored), 4, 'every entry stored';
  is $queries, 0, 'no identity query';
};

done_testing;
