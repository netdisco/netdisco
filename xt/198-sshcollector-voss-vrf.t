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
# vrfids commands (ARP, then IPv6 neighbors) name each VRF, so their blocks
# say which VRF a row is in and which VRFs were read.

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

# IPv4 entries by default; family 6 gives the IPv6 neighbors
sub entries_in {
  my ($result, $vrf, $family) = @_;
  my $v6 = (($family // 4) == 6);
  return [ map { "$_->{ip} $_->{mac}" }
    grep { $_->{vrf} eq $vrf and (($_->{ip} =~ m/:/) ? $v6 : !$v6) } @{ $result->{entries} } ];
}

# replace one command's captured output
sub with_output {
  my ($command, $output, $text) = @_;
  $text //= fixture_text('edge1');
  $text =~ s/^(#--- \Q$command\E\n).*?(?=^#---)/$1$output/ms or die "no section $command";
  return $text;
}

my $STAMP = "************************************************************************************\n"
  . "\t\tCommand Execution Time: Sat Oct 31 03:11:50 2026 UTC\n"
  . "************************************************************************************\n";
my $V6_CMD = 'show ipv6 neighbor vrfids 0-512';


my %EDGE1_READ = ('' => 1, red => 1, blue => 1, green => 1, grey => 1, MgmtRouter => 1);

subtest 'voss_arpnip_by_vrf__lab_capture__entries_carry_their_vrf' => sub {
  my $ssh = fake_ssh('edge1');
  my $result = by_vrf($ssh);

  is_deeply [$ssh->commands],
    ['terminal more disable', 'show ip vrf', 'show ip arp vrfids 0-512', $V6_CMD, 'exit'],
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
  is scalar(grep { $_->{ip} !~ m/:/ } @{ $result->{entries} }), 14, 'no other IPv4 rows';
  is_deeply [ sort keys %{ $result->{entries}->[0] } ], [qw/ip mac vrf/], 'entry keys';
  is_deeply $result->{vrf_read}, \%EDGE1_READ, 'every listed VRF read whole';
  is $result->{vrf_list_complete}, 1, 'list complete';
  is_deeply $result->{families}, [4, 6], 'both families';
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
  $text .= "#--- show ip arp vrfids 512\n" . ($text =~ m/^(\*+\n.*?\n\*+\n)/m)[0] . $mgmt
    . "#--- show ipv6 neighbor vrfids 512\n$STAMP\nInfo: IPV6 Instance does not exist for VRF with id: 512 \n\n";
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text), { vrfs => '512' });
  is_deeply $result->{entries}, [], 'no entries';
  is $result->{vrf_read}->{MgmtRouter}, 1, 'MgmtRouter read whole';
  is $result->{vrf_read}->{''}, 0, 'default table not read';
};

subtest 'voss_arpnip_by_vrf__vrfids_times_out__every_vrf_incomplete_no_ipv6_sent' => sub {
  my $ssh = fake_ssh('edge1', timeout_on => 'show ip arp vrfids 0-512');
  my $result = by_vrf($ssh);
  ok ref $result eq 'HASH', 'a result, not a failure';
  is_deeply $result->{vrf_read}, { map { ($_ => 0) } keys %EDGE1_READ }, 'every VRF incomplete';
  is $result->{vrf_list_complete}, 0, 'list not vouched after a timeout';
  is scalar(@{ $result->{entries} }), 14, 'the partial output still yields its rows';
  is scalar(grep { $_ eq $V6_CMD } $ssh->commands), 0, 'nothing sent into the unfinished reply';
  is_deeply $result->{families}, [4], 'IPv4 only';
  is_deeply [($ssh->commands)[-1]], ['exit'], 'session closed with exit';
};

subtest 'voss_arpnip_by_vrf__vrf_list_times_out__returns_undef' => sub {
  my $ssh = fake_ssh('edge1', timeout_on => 'show ip vrf');
  is by_vrf($ssh), undef, 'failure, so the worker defers';
  is_deeply [$ssh->commands], ['terminal more disable', 'show ip vrf', 'exit'],
    'stops after the timeout';
};

subtest 'voss_arpnip_by_vrf__configured_vrf_subset__list_incomplete' => sub {
  # the 0-512 capture stands in for the subset's output; what is under test
  # is that a configured subset never vouches for the VRF list
  (my $text = fixture_text('edge1'))
    =~ s/^#--- show ip arp vrfids 0-512$/#--- show ip arp vrfids 0-4/m;
  $text =~ s/^#--- \Q$V6_CMD\E$/#--- show ipv6 neighbor vrfids 0-4/m;
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

subtest 'voss_arpnip_by_vrf__arp_row_without_mac__counted_no_entry' => sub {
  # no capture shows an unresolved VOSS ARP row; the footer counts it either way
  (my $text = fixture_text('edge1'))
    =~ s/^(10\.100\.1\.10\s+)02:00:00:00:05:11(\s+41 )/${1}INCOMPLETE       $2/m
    or die 'red row not found';
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is scalar(@{ entries_in($result, 'red') }), 5, 'the row without a MAC gives no entry';
  is $result->{vrf_read}->{red}, 1, 'red still whole, the row was counted';
  is $result->{vrf_list_complete}, 1, 'list complete';
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
  is scalar(grep { $_->{ip} !~ m/:/ } @{ $result->{entries} }), 8, 'blue rows dropped';
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

subtest 'voss_arpnip_by_vrf__ipv6_lab_capture__neighbors_carry_their_vrf_compressed' => sub {
  my $result = by_vrf(fake_ssh('edge1'));
  is_deeply entries_in($result, '', 6), ['2001:db8:1255::13 00:00:00:00:00:01'], 'GlobalRouter neighbor';
  is_deeply entries_in($result, 'red', 6), [
    '2001:db8:1001::1 0c:00:5c:9e:d5:01', '2001:db8:1001::10 02:00:00:00:05:11',
    'fe80::e00:5cff:fe9e:d501 0c:00:5c:9e:d5:01',
  ], 'red neighbors, the router-own and link-local rows kept';
  is_deeply entries_in($result, 'blue', 6), [
    '2001:db8:1001::1 0c:00:5c:9e:d5:02', '2001:db8:1001::10 02:00:00:00:05:12',
    'fe80::e00:5cff:fe9e:d502 0c:00:5c:9e:d5:02',
  ], 'blue keeps the address red also holds';
  is_deeply entries_in($result, 'green', 6), [
    '2001:db8:1201::1 0c:00:5c:9e:d5:05', '2001:db8:1201::10 02:00:00:00:05:16',
    'fe80::e00:5cff:fe9e:d505 0c:00:5c:9e:d5:05',
  ], 'green neighbors';
  is_deeply entries_in($result, 'grey', 6), [], 'grey has none';
  is $result->{vrf_read}->{grey}, 1, 'an empty block reads whole';
  is $result->{vrf_read}->{MgmtRouter}, 1, 'a VRF with no IPv6 instance reads whole and empty';
};

subtest 'voss_arpnip_by_vrf__ipv6_second_lab_capture__global_host_read' => sub {
  my $result = by_vrf(fake_ssh('edge3'));
  ok scalar(grep { $_ eq '2001:db8:30::10 02:00:00:00:05:22' } @{ entries_in($result, '', 6) }),
    'the GlobalRouter host';
  is_deeply $result->{families}, [4, 6], 'both families';
  is $result->{vrf_list_complete}, 1, 'list complete';
};

subtest 'voss_arpnip_by_vrf__ipv6_command_refused__families_ipv4_only' => sub {
  foreach my $reply ("% Invalid input detected at '^' marker.\n", "\n Error : Invalid VRF ID \n\n") {
    my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => with_output($V6_CMD, $STAMP . $reply)));
    is_deeply $result->{families}, [4], 'IPv4 only';
    is_deeply $result->{vrf_read}, \%EDGE1_READ, 'IPv4 reads stand';
    is $result->{vrf_list_complete}, 1, 'list complete';
    is scalar(grep { $_->{ip} =~ m/:/ } @{ $result->{entries} }), 0, 'no IPv6 entries';
  }
};

subtest 'voss_arpnip_by_vrf__ipv6_times_out__families_ipv4_only' => sub {
  my $ssh = fake_ssh('edge1', timeout_on => $V6_CMD);
  my $result = by_vrf($ssh);
  is_deeply $result->{families}, [4], 'IPv4 only';
  is_deeply $result->{vrf_read}, \%EDGE1_READ, 'IPv4 reads stand';
  is scalar(grep { $_->{ip} =~ m/:/ } @{ $result->{entries} }), 0, 'partial IPv6 output dropped';
  is_deeply [($ssh->commands)[-1]], ['exit'], 'session closed with exit';
};

subtest 'voss_arpnip_by_vrf__ipv6_footer_count_mismatch__that_vrf_0' => sub {
  (my $text = fixture_text('edge1'))
    =~ s/(Neighbor Information - VRF red\n(?:.*\n)*?)3 out of 3 Total/${1}4 out of 4 Total/
    or die 'red neighbor footer not found';
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is $result->{vrf_read}->{red}, 0, 'red IPv6 counts a row not parsed';
  is $result->{vrf_read}->{blue}, 1, 'blue still whole';
  is $result->{vrf_list_complete}, 0, 'list not vouched';
};

subtest 'voss_arpnip_by_vrf__listed_vrf_without_ipv6_block__that_vrf_0' => sub {
  (my $text = fixture_text('edge1'))
    =~ s/^=+\n\s+Neighbor Information - VRF green\n(?:.*\n)*?\d+ out of \d+ Total Num of Neighbor Entries displayed\.\n//m
    or die 'green neighbor block not found';
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is $result->{vrf_read}->{green}, 0, 'green IPv6 not read';
  is $result->{vrf_read}->{red}, 1, 'red still whole';
};

subtest 'voss_arpnip_by_vrf__no_ipv6_instance_line__ranges_named_vrfs_whole' => sub {
  (my $text = fixture_text('edge1'))
    =~ s/^Info: IPV6 Instance does not exist for VRF with id: 512 $/Info: IPV6 Instance does not exist for VRF with id: 3-4,512 /m
    or die 'no-instance line not found';
  $text =~ s/^=+\n\s+Neighbor Information - VRF (?:green|grey)\n(?:.*\n)*?\d+ out of \d+ Total Num of Neighbor Entries displayed\.\n//mg;
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is $result->{vrf_read}->{$_}, 1, "$_ whole and empty" for qw/green grey MgmtRouter/;

  ($text = fixture_text('edge1')) =~ s/^Info: IPV6 Instance does not exist for VRF with id: 512 \n//m
    or die 'no-instance line not found';
  is by_vrf(Test::Netdisco::FakeSSH->new(text => $text))->{vrf_read}->{MgmtRouter}, 0,
    'without the line MgmtRouter has no IPv6 read';
};

subtest 'voss_arpnip_by_vrf__ipv6_row_without_mac__counted_no_entry' => sub {
  (my $text = fixture_text('edge1'))
    =~ s/^(2001:db8:1001:0:0:0:0:10\/ .*V-41 .*\n)\s+02:00:00:00:05:11\s*\n/$1/m
    or die 'red host row not found';
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is scalar(@{ entries_in($result, 'red', 6) }), 2, 'the row without a MAC gives no entry';
  is $result->{vrf_read}->{red}, 1, 'red still whole, the row was counted';
};

subtest 'voss_arpnip_by_vrf__learned_row_type_and_state__still_read' => sub {
  # the lab VM learns no IPv6 neighbor, so learned rows were never captured
  (my $text = fixture_text('edge1'))
    =~ s/^(2001:db8:1001:0:0:0:0:10\/\s+V-41\s+1\/4\s+)STATIC  REACHABLE/${1}DYNAMIC STALE    /m
    or die 'red host row not found';
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  ok scalar(grep { $_ eq '2001:db8:1001::10 02:00:00:00:05:11' } @{ entries_in($result, 'red', 6) }),
    'read whatever its TYPE and STATE';
  is $result->{vrf_read}->{red}, 1, 'red whole';
};

subtest 'voss_arpnip_by_vrf__unrecognized_ipv6_header__rows_dropped' => sub {
  (my $text = fixture_text('edge1')) =~ s/Neighbor Information - VRF blue$/Neighbor Information - VRF blue sky/m
    or die 'blue neighbor header not found';
  my $result = by_vrf(Test::Netdisco::FakeSSH->new(text => $text));
  is scalar(@{ entries_in($result, 'red', 6) }), 3, 'blue rows not stored under red';
  is scalar(@{ entries_in($result, 'blue', 6) }), 0, 'blue rows dropped';
  is $result->{vrf_read}->{blue}, 0, 'blue not read';
  is $result->{vrf_list_complete}, 0, 'list not vouched';
};

subtest 'voss_arpnip_by_vrf__debug_log__names_commands_and_families' => sub {
  my @logged;
  no warnings 'redefine';
  local *App::Netdisco::SSHCollector::Platform::VOSS::debug = sub { push @logged, join '', @_ };
  by_vrf(fake_ssh('edge1'));
  ok scalar(grep { m/\Q$V6_CMD\E/ } @logged), 'the IPv6 command is logged';
  ok scalar(grep { m/families \[4, 6\]/ } @logged), 'the families reported are logged';

  @logged = ();
  by_vrf(fake_ssh('edge1', timeout_on => $V6_CMD));
  ok scalar(grep { m/families \[4\]/ } @logged), 'IPv4 only after an IPv6 timeout';
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

# a session that cannot open its pty, as Net::OpenSSH reports a failed spawn
{
  package NoPtySSH;
  our @ISA = ('Test::Netdisco::FakeSSH');
  sub open2pty { my $self = shift; $self->{error} = 'spawn failed'; return () }
  sub error { return $_[0]{error} }
}

sub debug_lines_of {
  my $code = shift;
  my @logged;
  no warnings 'redefine';
  local *App::Netdisco::SSHCollector::Platform::VOSS::debug = sub { push @logged, join '', @_ };
  my $result = $code->();
  return ($result, @logged);
}

subtest 'voss_arpnip_by_vrf__pty_not_opened__returns_undef_logs_debug' => sub {
  my $ssh = NoPtySSH->new(fixture => "$FIXTURES/edge1.txt");
  my ($result, @logged) = debug_lines_of(sub { by_vrf($ssh) });
  is $result, undef, 'failure, so the worker defers';
  is_deeply [$ssh->commands], [], 'nothing sent';
  is scalar(grep { m/unable to run remote command \[edge\] spawn failed/ } @logged), 1, 'logged at debug with the error';
};

subtest 'voss_arpnip_by_vrf__terminal_more_disable_times_out__abandoned' => sub {
  my $ssh = fake_ssh('edge1', timeout_on => 'terminal more disable');
  my ($result, @logged) = debug_lines_of(sub { by_vrf($ssh) });
  is $result, undef, 'failure, so the worker defers';
  is_deeply [$ssh->commands], ['terminal more disable', 'exit'], 'session closed, nothing else sent';
  is scalar(grep { m/no prompt after terminal more disable \[edge\]/ } @logged), 1, 'the abandon is logged';
};

subtest 'voss_arpnip_by_vrf__terminal_more_disable_refused__abandoned' => sub {
  my $ssh = Test::Netdisco::FakeSSH->new(text => with_output('terminal more disable',
    "                    ^\n% Invalid input detected at '^' marker.\n\n"));
  my ($result, @logged) = debug_lines_of(sub { by_vrf($ssh) });
  is $result, undef, 'failure, so the worker defers';
  is_deeply [$ssh->commands], ['terminal more disable', 'exit'], 'session closed, nothing else sent';
  is scalar(grep { m/invalid command \[edge\]/ } @logged), 1, 'the abandon is logged';
};

subtest 'voss_arpnip_by_vrf__vrfs_setting_not_an_id_list__all_vrfs_asked' => sub {
  my $ssh = fake_ssh('edge1');
  my $result = by_vrf($ssh, { vrfs => 'red' });
  is +($ssh->commands)[2], 'show ip arp vrfids 0-512', 'a name is not sent; the whole range is';
  is $result->{vrf_list_complete}, 1, 'the whole range vouches for the list';
};

done_testing;
