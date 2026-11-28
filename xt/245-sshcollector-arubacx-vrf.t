#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::SSHCollector::Platform::ArubaCX;
use Test::Netdisco::FakeSSH;

use Dancer qw/:moose :script !pass/;

# ArubaCX arpnip, arpnip_by_vrf and subnets_by_vrf against AOS-CX 10.16
# captures: aoscx1 has four user VRFs with overlapping addresses and an empty
# default table, leaf1 an EVPN leaf with default-table rows and an empty IPv6
# table printed without its VRF column. Every row names its VRF and every
# table ends in a count, so a table is whole only when each line parsed and
# the count matches.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

my $FIXTURES = 'xt/data/sshcollector/arubacx';
my $CX = App::Netdisco::SSHCollector::Platform::ArubaCX->new;
my $VRF = 'show vrf';
my $ARP = 'show arp all-vrfs';
my $ND  = 'show ipv6 neighbors all-vrfs';
my $RT4 = 'show ip route all-vrfs';
my $RT6 = 'show ipv6 route all-vrfs';

my %AOSCX1_READ = ('' => 1, blue => 1, green => 1, grey => 1, red => 1);

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

sub prefixes_in {
  my ($result, $vrf) = @_;
  return [ map { "$_->{prefix}/$_->{len}" } @{ $result->{$vrf} || [] } ];
}

subtest 'arubacx_arpnip_by_vrf__lab_capture__entries_carry_their_vrf' => sub {
  my $ssh = fake_ssh('aoscx1');
  my $result = $CX->arpnip_by_vrf('aoscx1', $ssh, {});

  is_deeply [$ssh->commands], [$VRF, $ARP, $ND], 'the VRF list and the two all-vrfs tables';
  is_deeply entries_in($result, 'red'), [
    '192.0.2.2 02:00:00:00:0a:01', '198.51.100.2 02:00:00:00:0a:03',
    '2001:db8:95::2 02:00:00:00:0a:01', '2001:db8:96::2 02:00:00:00:0a:03',
    'fe80::2 02:00:00:00:0a:01', 'fe80::3 02:00:00:00:0a:03',
    'fe80::ff:fe00:a01 02:00:00:00:0a:01', 'fe80::ff:fe00:a03 02:00:00:00:0a:03',
  ], 'red rows, link-local kept';
  is_deeply entries_in($result, 'blue')->[0], '192.0.2.2 02:00:00:00:0a:02',
    'the same address in blue keeps its own MAC';
  is scalar(@{ $result->{entries} }), 19, 'four ARP rows and fifteen neighbors';
  is_deeply entries_in($result, ''), [], 'nothing under the default table';
  is_deeply $result->{vrf_read}, \%AOSCX1_READ, 'every listed VRF read whole, rows or not';
  is $result->{vrf_list_complete}, 1, 'list complete';
  is_deeply $result->{families}, [4, 6], 'both families read';
};

subtest 'arubacx_arpnip_by_vrf__default_vrf_rows__stored_under_empty_vrf' => sub {
  my $result = $CX->arpnip_by_vrf('leaf1', fake_ssh('leaf1'), {});
  is_deeply entries_in($result, ''), ['203.0.113.1 02:00:00:0b:3f:e4', '203.0.113.5 02:00:00:0b:c8:26'],
    'default rows under the default table';
  ok !(grep { $_->{vrf} eq 'default' } @{ $result->{entries} }), 'no entry named default';
  is_deeply entries_in($result, 'blue'), ['198.51.100.23 02:00:cb:15:00:51', '198.51.100.24 02:00:cb:15:00:71'],
    'rows learned over VXLAN parsed';
  is_deeply $result->{vrf_read}, { '' => 1, KA => 1, blue => 1, red => 1 }, 'every listed VRF read whole';
  is_deeply $result->{families}, [4, 6], 'an empty IPv6 table without a VRF column is whole';
};

subtest 'arubacx_arpnip_by_vrf__ipv6_table_times_out__vouches_ipv4_only' => sub {
  my $result = $CX->arpnip_by_vrf('aoscx1', fake_ssh('aoscx1', $ND), {});
  is_deeply $result->{families}, [4], 'IPv4 only';
  is_deeply $result->{vrf_read}, \%AOSCX1_READ, 'every VRF read whole for IPv4';
  is scalar(@{ $result->{entries} }), 4, 'the ARP rows';
};

subtest 'arubacx_arpnip_by_vrf__row_missing_from_count__family_unread' => sub {
  my $result = $CX->arpnip_by_vrf('aoscx1', fake_ssh('aoscx1-short'), {});
  is_deeply $result->{families}, [6], 'ARP not vouched when its count disagrees';
  is_deeply $result->{vrf_read}, \%AOSCX1_READ, 'VRFs read whole for IPv6';
  is scalar(grep { $_->{ip} !~ m/:/ } @{ $result->{entries} }), 3, 'the ARP rows that were read are still returned';
};

subtest 'arubacx_arpnip_by_vrf__table_cut_before_its_count__family_unread' => sub {
  my $result = $CX->arpnip_by_vrf('aoscx1', fake_ssh('aoscx1-truncated'), {});
  is_deeply $result->{families}, [6], 'ARP not vouched without its count';
  is scalar(grep { $_->{ip} !~ m/:/ } @{ $result->{entries} }), 2, 'the rows before the cut are returned';
};

subtest 'arubacx_arpnip_by_vrf__line_that_is_not_a_row__family_unread' => sub {
  # test input, not a capture: a line the parser does not know, count unchanged
  (my $text = fixture_text('aoscx1')) =~ s/^(Total Number Of ARP Entries)/unexpected line\n$1/m;
  my $result = $CX->arpnip_by_vrf('aoscx1', Test::Netdisco::FakeSSH->new(text => $text), {});
  is_deeply $result->{families}, [6], 'ARP not vouched';
};

subtest 'arubacx_arpnip_by_vrf__empty_output__family_unread' => sub {
  (my $text = fixture_text('aoscx1')) =~ s/^(#--- show arp all-vrfs\n).*?(?=^#--- |\z)/$1/ms;
  my $result = $CX->arpnip_by_vrf('aoscx1', Test::Netdisco::FakeSSH->new(text => $text), {});
  is_deeply $result->{families}, [6], 'no output is not an empty table';
};

subtest 'arubacx_arpnip_by_vrf__empty_vrf_list__list_not_complete' => sub {
  (my $text = fixture_text('aoscx1')) =~ s/^(#--- show vrf\n).*?(?=^#--- |\z)/$1/ms;
  my $result = $CX->arpnip_by_vrf('aoscx1', Test::Netdisco::FakeSSH->new(text => $text), {});
  is $result->{vrf_list_complete}, 0, 'empty output is not an empty list';
};

subtest 'arubacx_arpnip_by_vrf__failed_commands__logged_with_their_reason' => sub {
  my @logged;
  no warnings 'redefine';
  local *App::Netdisco::SSHCollector::Platform::ArubaCX::info = sub { push @logged, join '', @_ };
  $CX->arpnip_by_vrf('aoscx1', fake_ssh('aoscx1', $ND), {});
  like $logged[0] // '', qr/show ipv6 neighbors all-vrfs failed: .*timed out/, 'timeout named';
  @logged = ();
  $CX->arpnip_by_vrf('aoscx1', fake_ssh('aoscx1-auditors'), {});
  like $logged[1] // '', qr/show arp all-vrfs returned an error: Invalid input: arp/, 'error line named';
};

subtest 'arubacx_arpnip_by_vrf__vrf_list_times_out__only_vrfs_with_rows_vouched' => sub {
  my $result = $CX->arpnip_by_vrf('aoscx1', fake_ssh('aoscx1', $VRF), {});
  is $result->{vrf_list_complete}, 0, 'list not complete';
  is_deeply $result->{vrf_read}, { blue => 1, green => 1, red => 1 }, 'VRFs named by rows';
  is scalar(@{ $result->{entries} }), 19, 'every row still returned';
};

subtest 'arubacx_arpnip_by_vrf__read_only_auditors_account__returns_undef' => sub {
  is $CX->arpnip_by_vrf('aoscx1', fake_ssh('aoscx1-auditors'), {}), undef,
    'Invalid input replies read nothing, so the worker defers';
};

subtest 'arubacx_arpnip_by_vrf__both_tables_time_out__returns_undef' => sub {
  is $CX->arpnip_by_vrf('aoscx1', fake_ssh('aoscx1', $ARP, $ND), {}), undef, 'nothing read';
};

subtest 'arubacx_subnets_by_vrf__lab_capture__connected_prefixes_per_vrf' => sub {
  my $ssh = fake_ssh('aoscx1');
  my $result = $CX->subnets_by_vrf('aoscx1', $ssh, {});
  is_deeply [$ssh->commands], [$RT4, $RT6], 'the two all-vrfs route tables';
  is_deeply prefixes_in($result, 'red'),
    ['192.0.2.0/24', '198.51.100.0/24', '2001:db8:95::/64', '2001:db8:96::/64'], 'red connected routes';
  is_deeply prefixes_in($result, 'green'), ['2001:db8:98::/64'], 'green has IPv6 only';
  is_deeply $result->{grey}, [], 'a VRF with only local routes is listed empty';
  ok !exists $result->{default}, 'a VRF absent from both tables is not listed';
};

subtest 'arubacx_subnets_by_vrf__ecmp_and_bgp_rows__only_connected_kept' => sub {
  # leaf1's capture has no IPv6 route table, so that command times out here
  my $ssh = Test::Netdisco::FakeSSH->new(text => fixture_text('leaf1') . "#--- $RT6\n");
  $ssh->timeout_on($RT6);
  my $result = $CX->subnets_by_vrf('leaf1', $ssh, {});
  is_deeply prefixes_in($result, 'default'), ['203.0.113.0/31', '203.0.113.4/31'],
    'OSPF routes and the second ECMP next hop skipped';
  is_deeply prefixes_in($result, 'red'), ['198.51.100.0/24'], 'EVPN route skipped';
  is_deeply prefixes_in($result, 'KA'), ['203.0.113.6/31'], 'KA connected route';
};

subtest 'arubacx_subnets_by_vrf__route_missing_from_count__family_contributes_nothing' => sub {
  my $result = $CX->subnets_by_vrf('aoscx1', fake_ssh('aoscx1-short'), {});
  is_deeply prefixes_in($result, 'blue'), ['2001:db8:95::/64', '2001:db8:97::/64'], 'IPv6 only';
};

subtest 'arubacx_subnets_by_vrf__table_cut_before_its_count__family_contributes_nothing' => sub {
  my $result = $CX->subnets_by_vrf('aoscx1', fake_ssh('aoscx1-truncated'), {});
  is_deeply prefixes_in($result, 'blue'), ['2001:db8:95::/64', '2001:db8:97::/64'], 'IPv6 only';
};

subtest 'arubacx_subnets_by_vrf__line_that_is_not_a_route__family_contributes_nothing' => sub {
  # test input, not a capture: a line the parser does not know, count unchanged
  (my $text = fixture_text('aoscx1')) =~ s/^(Total Route Count : 9)/unexpected line\n$1/m;
  my $result = $CX->subnets_by_vrf('aoscx1', Test::Netdisco::FakeSSH->new(text => $text), {});
  is_deeply prefixes_in($result, 'blue'), ['2001:db8:95::/64', '2001:db8:97::/64'], 'IPv6 only';
};

subtest 'arubacx_subnets_by_vrf__empty_output__family_contributes_nothing' => sub {
  (my $text = fixture_text('aoscx1')) =~ s/^(#--- show ipv6 route all-vrfs\n).*?(?=^#--- |\z)/$1/ms;
  my $ssh = Test::Netdisco::FakeSSH->new(text => $text);
  my @logged;
  no warnings 'redefine';
  local *App::Netdisco::SSHCollector::Platform::ArubaCX::info = sub { push @logged, join '', @_ };
  my $result = $CX->subnets_by_vrf('aoscx1', $ssh, {});
  is_deeply prefixes_in($result, 'green'), [], 'no IPv6 prefixes from empty output';
  like $logged[0] // '', qr/no route count/, 'logged as unread';
};

subtest 'arubacx_subnets_by_vrf__both_tables_fail__returns_undef' => sub {
  is $CX->subnets_by_vrf('aoscx1', fake_ssh('aoscx1-auditors'), {}), undef, 'nothing read';
};

subtest 'arubacx_arpnip__lab_capture__both_families_without_vrf' => sub {
  my $ssh = fake_ssh('aoscx1');
  my @rows = $CX->arpnip('aoscx1', $ssh, {});
  is_deeply [$ssh->commands], [$ARP, $ND], 'the two all-vrfs tables, no VRF list';
  is scalar(@rows), 19, 'four ARP rows and fifteen neighbors';
  is_deeply [ sort map { "$_->{ip} $_->{mac}" } grep { $_->{ip} !~ m/:/ } @rows ], [
    '192.0.2.2 02:00:00:00:0a:01', '192.0.2.2 02:00:00:00:0a:02',
    '198.51.100.2 02:00:00:00:0a:03', '203.0.113.2 02:00:00:00:0a:03',
  ], 'IPv4 rows';
  is_deeply [ sort keys %{ $rows[0] } ], [qw/ip mac/], 'no VRF in a row';
};

subtest 'arubacx_arpnip__short_ipv6_table__rows_read_still_returned' => sub {
  my @rows = $CX->arpnip('aoscx1', fake_ssh('aoscx1', $ND), {});
  is scalar(@rows), 4, 'the ARP rows';
  @rows = $CX->arpnip('aoscx1', fake_ssh('aoscx1-truncated'), {});
  is scalar(grep { $_->{ip} !~ m/:/ } @rows), 2, 'ARP rows before the cut';
};

# test input, not a capture: ARP rows without the VRF column, as in the
# show arp example the original arpnip was written from
sub without_vrf_column {
  (my $text = fixture_text('aoscx1')) =~ s/^(\d+\.\d+\.\d+\.\d+\s.*?reachable)\s+\S+\s*$/$1/mg;
  return Test::Netdisco::FakeSSH->new(text => $text);
}

subtest 'arubacx_arpnip__rows_without_vrf_column__still_returned' => sub {
  my @rows = $CX->arpnip('aoscx1', without_vrf_column(), {});
  is scalar(grep { $_->{ip} !~ m/:/ } @rows), 4, 'the ARP rows';
};

subtest 'arubacx_arpnip_by_vrf__rows_without_vrf_column__family_unread' => sub {
  my $result = $CX->arpnip_by_vrf('aoscx1', without_vrf_column(), {});
  is_deeply $result->{families}, [6], 'ARP not vouched';
  is scalar(grep { $_->{ip} !~ m/:/ } @{ $result->{entries} }), 0, 'no ARP entry without its VRF';
};

subtest 'arubacx_arpnip__both_tables_fail__returns_empty_list' => sub {
  is_deeply [ $CX->arpnip('aoscx1', fake_ssh('aoscx1-auditors'), {}) ], [], 'nothing';
};

done_testing;
