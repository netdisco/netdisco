#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::SSHCollector::Platform::EOS;
use Test::Netdisco::FakeSSH;

use Dancer qw/:moose :script !pass/;

# EOS arpnip_by_vrf against cEOS 4.36.2F lab captures: the vrf all JSON is
# keyed by VRF name, so each entry's VRF and the VRFs read come from its keys.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

my $FIXTURES = 'xt/data/sshcollector/eos';
my $EOS = App::Netdisco::SSHCollector::Platform::EOS->new;
my $ARP = 'show ip arp vrf all | json | no-more';
my $ND  = 'show ipv6 neighbor vrf all | json | no-more';

sub fixture_text { local (@ARGV, $/) = ("$FIXTURES/$_[0].txt"); return scalar <> }

sub fake_ssh {
  my ($host, @timeouts) = @_;
  my $ssh = Test::Netdisco::FakeSSH->new(fixture => "$FIXTURES/$host.txt");
  $ssh->timeout_on($_) for @timeouts;
  return $ssh;
}

sub entries_in {
  my ($result, $vrf) = @_;
  return [ sort { $a cmp $b } map { "$_->{ip} $_->{mac}" } grep { $_->{vrf} eq $vrf } @{ $result->{entries} } ];
}

sub capture_info_lines {
  my $code = shift;
  my @logged;
  no warnings 'redefine';
  local *App::Netdisco::SSHCollector::Platform::EOS::info = sub { push @logged, join '', @_ };
  my $result = $code->();
  return ($result, @logged);
}

my %R3_READ = (MGMT => 1, RED_VRF => 1, Red => 1, '' => 1);

subtest 'eos_arpnip_by_vrf__lab_capture__entries_carry_their_vrf' => sub {
  my $ssh = fake_ssh('r3');
  my $result = $EOS->arpnip_by_vrf('r3', $ssh, {});

  is_deeply [$ssh->commands], [$ARP, $ND], 'the two vrf all commands';
  is_deeply entries_in($result, 'MGMT'), ['172.20.20.1 be57.40b3.ef86'], 'MGMT row under MGMT';
  is_deeply entries_in($result, 'Red'), ['10.111.3.2 0200.0000.1103'], 'Red row under Red, case kept';
  is_deeply entries_in($result, ''), [], 'nothing under the default table';
  is scalar(@{ $result->{entries} }), 2, 'no other rows';
  is_deeply [ sort keys %{ $result->{entries}->[0] } ], [qw/iface ip mac vrf/],
    'IPv4 entry keys keep iface, as arpnip does';
  is_deeply $result->{vrf_read}, \%R3_READ, 'every VRF in both outputs read whole';
  is $result->{vrf_list_complete}, 1, 'list complete';
};

subtest 'eos_arpnip_by_vrf__default_key__maps_to_empty_vrf' => sub {
  my $result = $EOS->arpnip_by_vrf('r1', fake_ssh('r1'), {});
  is_deeply entries_in($result, ''), ['172.20.20.1 be57.40b3.ef86'], 'default row under the default table';
  is_deeply entries_in($result, 'RED'), ['10.111.1.2 0200.0000.1101'], 'RED row under RED';
  ok !(grep { $_->{vrf} eq 'default' } @{ $result->{entries} }), 'no entry named default';
  is_deeply $result->{vrf_read}, { RED => 1, '' => 1 }, 'default read as the empty VRF';
};

subtest 'eos_arpnip_by_vrf__empty_vrf__read_whole_with_no_entries' => sub {
  my $result = $EOS->arpnip_by_vrf('r3', fake_ssh('r3'), {});
  is_deeply entries_in($result, 'RED_VRF'), [], 'no RED_VRF entries';
  is $result->{vrf_read}->{RED_VRF}, 1, 'RED_VRF read whole';
};

subtest 'eos_arpnip_by_vrf__ipv6_neighbor__stored_under_its_vrf' => sub {
  my $result = $EOS->arpnip_by_vrf('r3', fake_ssh('r3-ipv6'), {});
  is_deeply entries_in($result, 'Red'),
    ['10.111.3.2 0200.0000.1103', '2001:db8:111:3::2 0200.0000.1103'], 'IPv6 neighbor under Red';
  my ($v6) = grep { $_->{ip} =~ m/:/ } @{ $result->{entries} };
  is_deeply [ sort keys %$v6 ], [qw/ip mac vrf/], 'IPv6 entry keys, no iface as in arpnip';
  is_deeply $result->{vrf_read}, \%R3_READ, 'every VRF read whole';
};

subtest 'eos_arpnip_by_vrf__ipv6_command_fails__every_vrf_incomplete' => sub {
  my ($result, @logged) = capture_info_lines(sub { $EOS->arpnip_by_vrf('r3', fake_ssh('r3', $ND), {}) });
  ok ref $result eq 'HASH', 'a result, not a failure';
  is_deeply $result->{vrf_read}, { map { ($_ => 0) } keys %R3_READ }, 'every VRF incomplete';
  is $result->{vrf_list_complete}, 0, 'list incomplete';
  is scalar(@{ $result->{entries} }), 2, 'IPv4 entries still returned';
  is scalar(@logged), 1, 'one info line';
  like $logged[0] // '', qr/IPv6 neighbor command/, 'names the failed command';

  ($result) = $EOS->arpnip_by_vrf('r3', fake_ssh('r3', $ARP), {});
  is_deeply $result->{vrf_read}, { map { ($_ => 0) } keys %R3_READ }, 'IPv4 failing: every VRF incomplete';
  is $result->{vrf_list_complete}, 0, 'IPv4 failing: list incomplete';
};

subtest 'eos_arpnip_by_vrf__undecodable_json__list_incomplete' => sub {
  (my $text = fixture_text('r3')) =~ s/(#--- \Q$ND\E\n(?:.*\n){5})(?:.*\n)*/$1/
    or die 'IPv6 section not found';
  my ($result, @logged) = capture_info_lines(sub {
    $EOS->arpnip_by_vrf('r3', Test::Netdisco::FakeSSH->new(text => $text), {}) });
  is $result->{vrf_list_complete}, 0, 'list incomplete';
  is_deeply $result->{vrf_read}, { map { ($_ => 0) } keys %R3_READ }, 'every VRF incomplete';
  is scalar(@logged), 1, 'one info line';

  ($text = fixture_text('r3')) =~ s/#--- \Q$ND\E\n(?:.*\n)*/#--- $ND\n{ "notVrfs": {} }\n/;
  $result = $EOS->arpnip_by_vrf('r3', Test::Netdisco::FakeSSH->new(text => $text), {});
  is $result->{vrf_list_complete}, 0, 'JSON without vrfs: list incomplete';
  is $result->{vrf_read}->{Red}, 0, 'JSON without vrfs: Red incomplete';
};

subtest 'eos_arpnip_by_vrf__vrf_missing_from_one_family__incomplete' => sub {
  (my $text = fixture_text('r3')) =~ s/(#--- \Q$ND\E\n(?:.*\n)*?\s*)"RED_VRF"/$1"OTHER"/
    or die 'IPv6 RED_VRF not found';
  my $result = $EOS->arpnip_by_vrf('r3', Test::Netdisco::FakeSSH->new(text => $text), {});
  is $result->{vrf_read}->{RED_VRF}, 0, 'RED_VRF listed only for IPv4';
  is $result->{vrf_read}->{OTHER}, 0, 'OTHER listed only for IPv6';
  is $result->{vrf_read}->{Red}, 1, 'Red still whole';
};

subtest 'eos_arpnip_by_vrf__vrf_without_neighbor_array__marked_incomplete' => sub {
  # X is listed by both commands with no table: not read, so never retired
  my $text = "#--- $ARP\n" . '{"vrfs":{"X":{"totalEntries":0},"A":{"ipV4Neighbors":[]}}}' . "\n"
           . "#--- $ND\n"  . '{"vrfs":{"X":{"totalEntries":0},"A":{"ipV6Neighbors":[]}}}' . "\n";
  my $result = $EOS->arpnip_by_vrf('r3', Test::Netdisco::FakeSSH->new(text => $text), {});
  is_deeply $result->{vrf_read}, { X => 0, A => 1 }, 'X present and incomplete, A whole';
  is_deeply $result->{entries}, [], 'no entries';

  $text =~ s/"A":\{"ipV6Neighbors":\[\]\}/"A":{"totalEntries":0}/ or die 'A not found';
  $result = $EOS->arpnip_by_vrf('r3', Test::Netdisco::FakeSSH->new(text => $text), {});
  is $result->{vrf_read}->{A}, 0, 'array in one family only: incomplete';
};

subtest 'eos_arpnip_by_vrf__multi_interface_entry__split_as_arpnip' => sub {
  (my $text = fixture_text('r3')) =~ s/"interface": "Ethernet3"/"interface": "Vlan3134, Port-Channel46"/
    or die 'Red interface not found';
  my $result = $EOS->arpnip_by_vrf('r3', Test::Netdisco::FakeSSH->new(text => $text), {});
  is_deeply [ sort { $a cmp $b } map { $_->{iface} } grep { $_->{vrf} eq 'Red' } @{ $result->{entries} } ],
    ['Port-Channel46', 'Vlan3134'], 'one entry per interface';
};

subtest 'eos_arpnip_by_vrf__both_commands_fail__returns_undef' => sub {
  my ($result, @logged) = capture_info_lines(sub { $EOS->arpnip_by_vrf('r3', fake_ssh('r3', $ARP, $ND), {}) });
  is $result, undef, 'failure, so the worker defers';
  is scalar(@logged), 2, 'one info line per failed command';
};

subtest 'eos_arpnip__lab_capture__unchanged_from_today' => sub {
  my $ssh = fake_ssh('r3-ipv6');
  my @rows = $EOS->arpnip('r3', $ssh, {});
  is_deeply [$ssh->commands], [$ARP, $ND], 'commands unchanged';
  is_deeply [ sort { $a cmp $b } map { join ' ', $_->{ip}, $_->{mac}, ($_->{iface} // '-') } @rows ], [
    '10.111.3.2 0200.0000.1103 Ethernet3',
    '172.20.20.1 be57.40b3.ef86 Management0',
    '2001:db8:111:3::2 0200.0000.1103 -',
  ], 'flat list';
  is_deeply [ sort { $a cmp $b } map { join ',', sort keys %$_ } @rows ], ['iface,ip,mac', 'iface,ip,mac', 'ip,mac'],
    'no vrf key; iface on IPv4 only';

  (my $text = fixture_text('r3'))
    =~ s/"interface": "Ethernet3"/"interface": "Vlan3134, Port-Channel46"/ or die;
  $text =~ s/"interface": "Management0"/"interface": ""/ or die;
  @rows = $EOS->arpnip('r3', Test::Netdisco::FakeSSH->new(text => $text), {});
  is_deeply [ sort { $a cmp $b } map { "$_->{ip} $_->{iface}" } @rows ],
    ['10.111.3.2 Port-Channel46', '10.111.3.2 Vlan3134'],
    'multi-interface split; an entry with no interface yields no row, as today';

  my ($result, @logged) = capture_info_lines(sub { [ $EOS->arpnip('r3', fake_ssh('r3', $ARP, $ND), {}) ] });
  is_deeply $result, [], 'both failing: no rows';
  is scalar(@logged), 2, 'both failing: one info line per command';
};

done_testing;
