#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::SSHCollector::Platform::VOSS;
use Test::Netdisco::FakeSSH;

use Dancer qw/:moose :script !pass/;

# VOSS arpnip_by_vrf against Fabric Engine 9.4 lab captures: the all-VRF
# vrfids command names each VRF, so its blocks say which VRF a row is in
# and which VRFs were read.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

my $FIXTURES = 'xt/data/sshcollector/voss';
my $VOSS = App::Netdisco::SSHCollector::Platform::VOSS->new;

sub fake_ssh {
  my ($host, %opts) = @_;
  my $ssh = Test::Netdisco::FakeSSH->new(fixture => "$FIXTURES/$host.txt");
  $ssh->timeout_on($opts{timeout_on}) if $opts{timeout_on};
  return $ssh;
}

sub by_vrf {
  my ($ssh, $auth) = @_;
  my $guard = $ssh->install_expect;
  return $VOSS->arpnip_by_vrf('edge', $ssh, ($auth || {}));
}

sub fixture_text { local (@ARGV, $/) = ("$FIXTURES/$_[0].txt"); return scalar <> }

sub entries_in {
  my ($result, $vrf) = @_;
  return [ map { "$_->{ip} $_->{mac}" } grep { $_->{vrf} eq $vrf } @{ $result->{entries} } ];
}

my %EDGE1_READ = ('' => 1, red => 1, blue => 1, green => 1, grey => 1, MgmtRouter => 1);

subtest 'voss_arpnip_by_vrf__lab_capture__entries_carry_their_vrf' => sub {
  my $ssh = fake_ssh('edge1');
  my $result = by_vrf($ssh);

  is_deeply [$ssh->commands],
    ['terminal more disable', 'show ip vrf', 'show ip arp vrfids 0-512', 'exit'],
    'commands in order';
  is_deeply entries_in($result, ''), ['10.255.0.13 00:00:00:00:00:01'], 'GlobalRouter rows under the default table';
  is_deeply entries_in($result, 'red'), [
    '10.100.1.1 0c:00:5f:a8:c5:01', '10.100.1.10 02:00:00:00:05:11', '10.100.1.255 ff:ff:ff:ff:ff:ff',
    '10.101.1.1 0c:00:5f:a8:c5:03', '10.101.1.10 02:00:00:00:05:15', '10.101.1.255 ff:ff:ff:ff:ff:ff',
  ], 'red rows under red';
  is_deeply entries_in($result, 'blue'), [
    '10.100.1.1 0c:00:5f:a8:c5:02', '10.100.1.10 02:00:00:00:05:12', '10.100.1.255 ff:ff:ff:ff:ff:ff',
    '10.102.1.1 0c:00:5f:a8:c5:04', '10.102.1.10 02:00:00:00:05:15', '10.102.1.255 ff:ff:ff:ff:ff:ff',
  ], 'blue rows under blue, the shared 10.100.1.1 with its own MAC';
  is_deeply entries_in($result, 'grey'), ['10.104.1.1 00:00:00:00:00:02'], 'grey row';
  is scalar(@{ $result->{entries} }), 14, 'no other rows';
  is_deeply [ sort keys %{ $result->{entries}->[0] } ], [qw/ip mac vrf/], 'entry keys';
  is_deeply $result->{vrf_read}, \%EDGE1_READ, 'every listed VRF read whole';
  is $result->{vrf_list_complete}, 1, 'list complete';
};

subtest 'voss_arpnip_by_vrf__second_lab_capture__same_ip_kept_per_vrf' => sub {
  my $result = by_vrf(fake_ssh('edge3'));
  is_deeply entries_in($result, ''), [
    '10.30.0.1 0c:00:1d:7a:51:04', '10.30.0.10 02:00:00:00:05:22',
    '10.30.0.255 ff:ff:ff:ff:ff:ff', '10.255.0.15 00:00:00:00:00:01',
  ], 'default table rows';
  is_deeply entries_in($result, 'red'), [
    '10.100.3.1 0c:00:1d:7a:51:01', '10.100.3.10 02:00:00:00:05:13', '10.100.3.255 ff:ff:ff:ff:ff:ff',
  ], 'red rows';
  is_deeply entries_in($result, 'blue'), [
    '10.100.3.1 0c:00:1d:7a:51:02', '10.100.3.10 02:00:00:00:05:14', '10.100.3.255 ff:ff:ff:ff:ff:ff',
  ], 'blue rows';
  is $result->{vrf_list_complete}, 1, 'list complete';
};

subtest 'voss_arpnip_by_vrf__empty_vrf_block__read_whole_with_no_entries' => sub {
  my $result = by_vrf(fake_ssh('edge1'));
  is_deeply entries_in($result, 'green'), [], 'no green entries';
  is $result->{vrf_read}->{green}, 1, 'green read whole';
};

subtest 'voss_arpnip_by_vrf__extn_block_header__does_not_reassign_rows' => sub {
  # MgmtRouter's Extn block is headed GlobalRouter; asked for MgmtRouter
  # alone, that header must not count as a read of the default table
  my $text = fixture_text('edge1');
  my ($mgmt) = $text =~ m/^#--- show ip arp vrfids 0-512\n(?:.*?\n)(?=\n=+\n\s+IP Arp - VRF MgmtRouter)(.*?)(?=^#---)/ms;
  ok length($mgmt // ''), 'MgmtRouter block cut from the 0-512 capture';
  $mgmt =~ s/^Info: No VRF exists with id: .*\n//m;
  $text .= "#--- show ip arp vrfids 512\n" . ($text =~ m/^(\*+\n.*?\n\*+\n)/m)[0] . $mgmt;
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text), { vrfs => '512' });
  is_deeply $result->{entries}, [], 'no entries';
  is $result->{vrf_read}->{MgmtRouter}, 1, 'MgmtRouter read whole';
  is $result->{vrf_read}->{''}, 0, 'default table not read';
};

subtest 'voss_arpnip_by_vrf__vrfids_times_out__every_vrf_incomplete' => sub {
  my $ssh = fake_ssh('edge1', timeout_on => 'show ip arp vrfids 0-512');
  my $result = by_vrf($ssh);
  ok ref $result eq 'HASH', 'a result, not a failure';
  is_deeply $result->{vrf_read}, { map { ($_ => 0) } keys %EDGE1_READ }, 'every VRF incomplete';
  is $result->{vrf_list_complete}, 0, 'list not vouched after a timeout';
  is scalar(@{ $result->{entries} }), 14, 'the partial output still yields its rows';
  is_deeply [($ssh->commands)[-1]], ['exit'], 'session closed with exit';
};

subtest 'voss_arpnip_by_vrf__vrf_list_times_out__list_incomplete' => sub {
  my $ssh = fake_ssh('edge1', timeout_on => 'show ip vrf');
  my $result = by_vrf($ssh);
  ok ref $result eq 'HASH', 'a result, not a failure';
  is $result->{vrf_list_complete}, 0, 'list incomplete';
  ok !(grep { $_ } values %{ $result->{vrf_read} }), 'no VRF read whole';
  is_deeply $result->{entries}, [], 'later output not parsed as fresh';
  is_deeply [$ssh->commands], ['terminal more disable', 'show ip vrf', 'exit'],
    'stops after the timeout';
};

subtest 'voss_arpnip_by_vrf__configured_vrf_subset__list_incomplete' => sub {
  # the 0-512 capture stands in for the subset's output; what is under test
  # is that a configured subset never vouches for the VRF list
  (my $text = fixture_text('edge1'))
    =~ s/^#--- show ip arp vrfids 0-512$/#--- show ip arp vrfids 0-4/m;
  my $ssh = Test::Netdisco::FakeSSH->new(text => $text);
  my $result = by_vrf($ssh, { vrfs => '0-4' });
  is_deeply [($ssh->commands)[2]], ['show ip arp vrfids 0-4'], 'configured subset sent';
  is $result->{vrf_list_complete}, 0, 'list incomplete';
  is $result->{vrf_read}->{red}, 1, 'VRFs read are still read whole';
};

subtest 'voss_arpnip_by_vrf__listed_vrf_without_block__incomplete' => sub {
  (my $text = fixture_text('edge1'))
    =~ s/^grey(\s+4\s)/purple$1/m;
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is $result->{vrf_read}->{purple}, 0, 'listed VRF with no block is incomplete';
};

subtest 'voss_arpnip_by_vrf__vrf_list_count_mismatch__list_incomplete' => sub {
  (my $text = fixture_text('edge1')) =~ s/^grey\s+4\s.*\n//m;
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is $result->{vrf_list_complete}, 0, 'five rows under a six-entry count line';
  is $result->{vrf_read}->{red}, 1, 'VRFs read are still read whole';

  ($text = fixture_text('edge1')) =~ s/^6 out of 6 Total/6 out of 7 Total/m;
  is by_vrf(Test::Netdisco::FakeSSH->new(text => $text))->{vrf_list_complete}, 0,
    'six rows shown out of seven';
};

subtest 'voss_arpnip_by_vrf__gt_sign_inside_output__does_not_end_the_read' => sub {
  # a fabric-learned row can show a remote system name in TUNNEL; a bare >
  # there once ended the read mid-block and vouched the cut VRF whole
  (my $text = fixture_text('edge1'))
    =~ s/^(10\.100\.1\.10\s+02:00:00:00:05:11\s+41\s+1\/4\s+DYNAMIC 2143\s+)    /${1}BEB>/m
    or die 'red row not found';
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is scalar(@{ entries_in($result, 'red') }), 6, 'all six red rows read';
  is_deeply $result->{vrf_read}, \%EDGE1_READ, 'every VRF read whole';
};

subtest 'voss_arpnip_by_vrf__output_cut_before_block_footer__vrf_not_read_whole' => sub {
  # what a stray prompt match leaves: the output ends at the prompt part way
  # through red's block, so red has no footer
  (my $text = fixture_text('edge1'))
    =~ s/^(10\.100\.1\.10\s+02:00:00:00:05:11 .*\n)(?:.*\n)*?(?=#--- show ip arp vrfids 999)/$1/m
    or die 'red row not found';
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is scalar(@{ entries_in($result, 'red') }), 2, 'the two rows before the cut';
  is $result->{vrf_read}->{red}, 0, 'red not read whole';
  is $result->{vrf_read}->{''}, 1, 'the block before it was';
  is $result->{vrf_list_complete}, 0, 'list not vouched';
};

subtest 'voss_arpnip_by_vrf__block_footer_count_mismatch__vrf_incomplete' => sub {
  (my $text = fixture_text('edge1'))
    =~ s/(IP Arp - VRF blue\n(?:.*\n)*?)6 out of 15 ARP/${1}7 out of 15 ARP/
    or die 'blue footer not found';
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is $result->{vrf_read}->{blue}, 0, 'blue footer counts a row not parsed';
  is $result->{vrf_read}->{red}, 1, 'red still whole';
  is $result->{vrf_list_complete}, 0, 'list not vouched';
};

subtest 'voss_arpnip_by_vrf__unrecognized_arp_header__rows_dropped' => sub {
  (my $text = fixture_text('edge1')) =~ s/IP Arp - VRF blue$/IP Arp - VRF blue sky/m
    or die 'blue header not found';
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is scalar(@{ entries_in($result, 'red') }), 6, 'blue rows not stored under red';
  is scalar(@{ $result->{entries} }), 8, 'blue rows dropped';
  is $result->{vrf_read}->{blue}, 0, 'blue not read';
  is $result->{vrf_list_complete}, 0, 'list not vouched';
};

subtest 'voss_arpnip_by_vrf__prompt_form_not_seen__logs_skip_at_info' => sub {
  my @logged;
  no warnings 'redefine';
  local *App::Netdisco::SSHCollector::Platform::VOSS::info = sub { push @logged, join '', @_ };
  (my $text = fixture_text('edge1')) =~ s/^#prompt: edge1:1>$/#prompt: edge1>/m or die 'prompt not found';
  my $ssh = Test::Netdisco::FakeSSH->new(text => $text);
  is by_vrf($ssh), undef, 'failure, so the worker defers';
  is scalar(@logged), 1, 'one info line';
  like $logged[0] // '', qr/<hostname>:<N>>.*VRF collection by CLI was skipped for this device/,
    'names the expected prompt form and the skip';
};

subtest 'voss_arpnip_by_vrf__invalid_vrf_id_error__returns_undef' => sub {
  my $ssh = fake_ssh('edge1');
  is by_vrf($ssh, { vrfs => '999' }), undef, 'failure, so the worker defers';
  is_deeply [($ssh->commands)[2]], ['show ip arp vrfids 999'], 'configured id sent';
};

subtest 'voss_arpnip__lab_capture__unchanged_from_today' => sub {
  my $ssh = fake_ssh('edge1');
  my $guard = $ssh->install_expect;
  my @rows = $VOSS->arpnip('edge', $ssh, {});
  is_deeply [$ssh->commands], ['terminal more disable', 'show ip arp vrfids 0-512', 'exit'],
    'commands unchanged';
  is_deeply [ map { "$_->{ip} $_->{mac}" } @rows ], [
    '10.255.0.13 00:00:00:00:00:01',
    '10.100.1.1 0c:00:5f:a8:c5:01', '10.100.1.10 02:00:00:00:05:11', '10.100.1.255 ff:ff:ff:ff:ff:ff',
    '10.101.1.1 0c:00:5f:a8:c5:03', '10.101.1.10 02:00:00:00:05:15', '10.101.1.255 ff:ff:ff:ff:ff:ff',
    '10.100.1.1 0c:00:5f:a8:c5:02', '10.100.1.10 02:00:00:00:05:12', '10.100.1.255 ff:ff:ff:ff:ff:ff',
    '10.102.1.1 0c:00:5f:a8:c5:04', '10.102.1.10 02:00:00:00:05:15', '10.102.1.255 ff:ff:ff:ff:ff:ff',
    '10.104.1.1 00:00:00:00:00:02',
  ], 'flat list in device order';
  is_deeply [ sort keys %{ $rows[0] } ], [qw/ip mac/], 'no vrf key';
};

done_testing;
