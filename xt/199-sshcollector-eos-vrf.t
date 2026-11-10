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

# EOS arpnip_by_vrf and subnets_by_vrf against cEOS 4.36.2F lab captures: the
# vrf all JSON is keyed by VRF name, so each entry's VRF and the VRFs read come
# from its keys.

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
  is_deeply $result->{families}, [4, 6], 'ARP and IPv6 neighbors both read';
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

subtest 'eos_arpnip_by_vrf__ipv6_command_fails__vouches_ipv4_only' => sub {
  my ($result, @logged) = capture_info_lines(sub { $EOS->arpnip_by_vrf('r3', fake_ssh('r3', $ND), {}) });
  ok ref $result eq 'HASH', 'a result, not a failure';
  is_deeply $result->{families}, [4], 'IPv4 only';
  is_deeply $result->{vrf_read}, \%R3_READ, 'every VRF the ARP output listed read whole';
  is $result->{vrf_list_complete}, 1, 'the ARP output listed every VRF';
  is scalar(@{ $result->{entries} }), 2, 'IPv4 entries returned';
  is scalar(@logged), 1, 'one info line';
  like $logged[0] // '', qr/IPv6 neighbor command/, 'names the failed command';
};

subtest 'eos_arpnip_by_vrf__ipv4_command_fails__vouches_ipv6_only' => sub {
  my ($result) = $EOS->arpnip_by_vrf('r3', fake_ssh('r3-ipv6', $ARP), {});
  is_deeply $result->{families}, [6], 'IPv6 only';
  is_deeply $result->{vrf_read}, \%R3_READ, 'every VRF the IPv6 output listed read whole';
  is $result->{vrf_list_complete}, 1, 'the IPv6 output listed every VRF';
  is_deeply [ map { $_->{ip} } @{ $result->{entries} } ], ['2001:db8:111:3::2'], 'IPv6 entries only';
};

subtest 'eos_arpnip_by_vrf__undecodable_ipv6_json__vouches_ipv4_only' => sub {
  (my $text = fixture_text('r3')) =~ s/(#--- \Q$ND\E\n(?:.*\n){5})(?:.*\n)*/$1/
    or die 'IPv6 section not found';
  my ($result, @logged) = capture_info_lines(sub {
    $EOS->arpnip_by_vrf('r3', Test::Netdisco::FakeSSH->new(text => $text), {}) });
  is_deeply $result->{families}, [4], 'IPv6 undecodable: IPv4 only';
  is $result->{vrf_list_complete}, 1, 'list complete from the ARP output';
  is_deeply $result->{vrf_read}, \%R3_READ, 'VRFs vouched from the ARP output';
  is scalar(@logged), 1, 'one info line';

  ($text = fixture_text('r3')) =~ s/#--- \Q$ND\E\n(?:.*\n)*/#--- $ND\n{ "notVrfs": {} }\n/;
  $result = $EOS->arpnip_by_vrf('r3', Test::Netdisco::FakeSSH->new(text => $text), {});
  is_deeply $result->{families}, [4], 'JSON without vrfs: IPv4 only';
  is $result->{vrf_read}->{Red}, 1, 'JSON without vrfs: Red vouched for IPv4';
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

subtest 'eos_arpnip_by_vrf__neighbor_without_interface__still_reported' => sub {
  (my $text = fixture_text('r3')) =~ s/"interface": "Management0"/"interface": ""/ or die 'MGMT interface not found';
  my $result = $EOS->arpnip_by_vrf('r3', Test::Netdisco::FakeSSH->new(text => $text), {});
  my @mgmt = grep { $_->{vrf} eq 'MGMT' } @{ $result->{entries} };
  is scalar(@mgmt), 1, 'empty interface: one entry';
  is_deeply [ sort keys %{ $mgmt[0] } ], [qw/ip mac vrf/], 'empty interface: no iface';

  ($text = fixture_text('r3')) =~ s/,\s*"interface": "Management0"//
    or die 'MGMT interface not found';
  $result = $EOS->arpnip_by_vrf('r3', Test::Netdisco::FakeSSH->new(text => $text), {});
  @mgmt = grep { $_->{vrf} eq 'MGMT' } @{ $result->{entries} };
  is scalar(@mgmt), 1, 'missing interface: one entry';
  ok !exists $mgmt[0]->{iface}, 'missing interface: no iface';
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

my $V4_ROUTES = 'show ip route vrf all connected | json | no-more';
my $V6_ROUTES = 'show ipv6 route vrf all connected | json | no-more';

sub fake_ssh_routes {
  my ($host, @timeouts) = @_;
  my $ssh = Test::Netdisco::FakeSSH->new(fixture => "$FIXTURES/$host-routes.txt");
  $ssh->timeout_on($_) for @timeouts;
  return $ssh;
}

# fixture text with each named command answered with the captured reply EOS
# gave to the misspelled twin of that command
sub routes_text_with_invalid {
  my ($host, @commands) = @_;
  my $text = fixture_text("$host-routes");
  foreach my $command (@commands) {
    (my $misspelled = $command) =~ s/connected/conected/;
    my ($reply) = $text =~ /^#--- \Q$misspelled\E\n(.*?)(?=^#---|\z)/ms or die;
    $text =~ s/(^#--- \Q$command\E\n).*?(?=^#---|\z)/$1$reply/ms or die;
  }
  return $text;
}

sub prefixes_by_vrf {
  my ($result) = @_;
  return { map { my $vrf = $_; ($vrf => [ sort map { "$_->{prefix}/$_->{len}" } @{ $result->{$vrf} } ]) } keys %$result };
}

my @R1_V4 = ('10.110.12.0/30', '10.110.13.0/30', '10.111.1.0/24', '10.120.0.1/32');
my @R1_V6 = ('2001:db8:110:12::/64', '2001:db8:110:13::/64', '2001:db8:111:1::/64', '2001:db8:120::1/128');

subtest 'eos_subnets_by_vrf__lab_capture__prefixes_keyed_by_vrf' => sub {
  my $ssh = fake_ssh_routes('r1');
  my $result = $EOS->subnets_by_vrf('r1', $ssh, {});

  is_deeply [$ssh->commands], [$V4_ROUTES, $V6_ROUTES], 'the two vrf all route commands';
  is_deeply prefixes_by_vrf($result), {
    default => ['172.20.20.0/24'],
    RED => [ sort @R1_V4, @R1_V6 ],
  }, 'IPv4 and IPv6 under the VRF EOS names, default kept as EOS gives it, nothing filtered here';

  $result = $EOS->subnets_by_vrf('r3', fake_ssh_routes('r3'), {});
  is_deeply prefixes_by_vrf($result), {
    default => [], MGMT => ['172.20.20.0/24'],
    RED_VRF => [ '10.110.13.0/30', '2001:db8:110:13::/64' ],
    Red => [ sort '10.110.23.0/30', '10.111.3.0/24', '2001:db8:110:23::/64', '2001:db8:111:3::/64' ],
  }, 'names differing only by case stay apart; a VRF with no routes maps to an empty list';
};

subtest 'eos_subnets_by_vrf__ipv6_command_fails__ipv4_still_returned' => sub {
  my $expected = { default => ['172.20.20.0/24'], RED => \@R1_V4 };

  my ($result, @logged) = capture_info_lines(sub {
    $EOS->subnets_by_vrf('r1', Test::Netdisco::FakeSSH->new(text => routes_text_with_invalid('r1', $V6_ROUTES)), {}) });
  is_deeply prefixes_by_vrf($result), $expected, 'undecodable IPv6 reply, IPv4 returned';
  is scalar(@logged), 1, 'the failure is logged once';

  ($result, @logged) = capture_info_lines(sub { $EOS->subnets_by_vrf('r1', fake_ssh_routes('r1', $V6_ROUTES), {}) });
  is_deeply prefixes_by_vrf($result), $expected, 'SSH error on IPv6, IPv4 returned';

  $result = $EOS->subnets_by_vrf('r1', fake_ssh_routes('r1', $V4_ROUTES), {});
  is_deeply prefixes_by_vrf($result), { default => [], RED => \@R1_V6 }, 'SSH error on IPv4, IPv6 returned';
};

subtest 'eos_subnets_by_vrf__ipv6_routes_not_a_hash__ipv4_still_returned' => sub {
  my $expected = { default => ['172.20.20.0/24'], RED => \@R1_V4 };
  foreach my $shape ('[]', '"none"') {
    (my $text = fixture_text('r1-routes')) =~ s/("routes": )\{\s*"2001:.*?\n {12}\}/$1$shape/s or die;
    my $result = eval { $EOS->subnets_by_vrf('r1', Test::Netdisco::FakeSSH->new(text => $text), {}) };
    is $@, '', "routes as $shape does not die";
    is_deeply prefixes_by_vrf($result), $expected, "IPv4 returned, the malformed IPv6 VRF contributes nothing ($shape)";
  }

  (my $text = fixture_text('r1-routes')) =~ s/("RED": )\{(\s*"routingDisabled": true)/$1"none"$2/ or die;
  $text =~ s/"none"\s*"routingDisabled": true.*?\n {8}\}\n/"none"\n/s or die;
  my $result = eval { $EOS->subnets_by_vrf('r1', Test::Netdisco::FakeSSH->new(text => $text), {}) };
  is $@, '', 'a VRF value that is not a hash does not die';
  is_deeply prefixes_by_vrf($result), $expected, 'IPv4 returned';
};

subtest 'eos_subnets_by_vrf__ipv6_vrfs_an_array__ipv4_still_returned' => sub {
  my $text = routes_text_with_invalid('r1', $V6_ROUTES);
  $text =~ s/(^#--- \Q$V6_ROUTES\E\n).*?(?=^#---|\z)/$1\{"vrfs": []\}\n/ms or die;
  my $result = eval { $EOS->subnets_by_vrf('r1', Test::Netdisco::FakeSSH->new(text => $text), {}) };
  is $@, '', 'does not die';
  is_deeply prefixes_by_vrf($result), { default => ['172.20.20.0/24'], RED => \@R1_V4 }, 'IPv4 returned';
};

subtest 'eos_subnets_by_vrf__empty_vrf_key__not_filed_as_global' => sub {
  (my $text = fixture_text('r1-routes')) =~ s/"RED": \{/"": {/g or die;
  my ($result, @logged) = capture_info_lines(sub {
    $EOS->subnets_by_vrf('r1', Test::Netdisco::FakeSSH->new(text => $text), {}) });
  is_deeply prefixes_by_vrf($result), { default => ['172.20.20.0/24'] }, 'the empty key contributes nothing, default untouched';
  ok scalar(@logged), 'it is logged';
};

subtest 'eos_subnets_by_vrf__both_fail__returns_undef' => sub {
  my ($result, @logged) = capture_info_lines(sub {
    [ $EOS->subnets_by_vrf('r1', fake_ssh_routes('r1', $V4_ROUTES, $V6_ROUTES), {}) ] });
  is_deeply $result, [undef], 'both commands error: undef';
  is scalar(@logged), 2, 'one info line per failed command';

  my $text = routes_text_with_invalid('r1', $V4_ROUTES, $V6_ROUTES);
  is $EOS->subnets_by_vrf('r1', Test::Netdisco::FakeSSH->new(text => $text), {}), undef,
    'both replies undecodable: undef';

  (my $novrfs = fixture_text('r1-routes')) =~ s/"vrfs"/"other"/g;
  is $EOS->subnets_by_vrf('r1', Test::Netdisco::FakeSSH->new(text => $novrfs), {}), undef,
    'JSON without vrfs: undef';
};

subtest 'eos_subnets__lab_capture__unchanged' => sub {
  my $ssh = fake_ssh_routes('r1');
  my @rows = $EOS->subnets('r1', $ssh, {});
  is_deeply [$ssh->commands], [$V4_ROUTES], 'one IPv4 command, as before';
  is_deeply [ sort @rows ], ['10.110.12.0/30', '10.110.13.0/30', '10.111.1.0/24', '172.20.20.0/24'],
    'flat IPv4 list, host routes dropped';
};

done_testing;
