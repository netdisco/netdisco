#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::SSHCollector::Platform::IOSXE;
use App::Netdisco::Worker::Plugin::Arpnip::Nodes ();
use Test::Netdisco::FakeSSH;

use Dancer qw/:moose :script !pass/;

# IOS-XE arpnip_by_vrf against an IOL-XE 17.18 lab capture: one command per
# VRF and address family, so a wrong VRF name or a timeout spoils only the
# reads it touches.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

my $FIXTURE = 'xt/data/sshcollector/iosxe/iol1.txt';
my $IOSXE = App::Netdisco::SSHCollector::Platform::IOSXE->new;

sub fixture_text { local (@ARGV, $/) = ($FIXTURE); return scalar <> }

sub fake_ssh {
  my (%opts) = @_;
  my $ssh = Test::Netdisco::FakeSSH->new(text => ($opts{text} // fixture_text()));
  $ssh->timeout_on($_) for @{ $opts{timeout_on} || [] };
  return $ssh;
}

sub by_vrf {
  my ($ssh) = @_;
  my $guard = $ssh->install_expect;
  return $IOSXE->arpnip_by_vrf('iol1', $ssh, {});
}

sub entries_in {
  my ($result, $vrf) = @_;
  return [ map { "$_->{ip} $_->{mac}" } grep { $_->{vrf} eq $vrf } @{ $result->{entries} } ];
}

# replace one command's captured output
sub with_output {
  my ($command, $output) = @_;
  (my $text = fixture_text()) =~ s/^(#--- \Q$command\E\n).*?(?=^#---)/$1$output/ms
    or die "no section $command";
  return $text;
}

my %LAB_READ = ('' => 1, blue => 1, green => 1, grey => 1, red => 1);

subtest 'arpnip_by_vrf__lab_capture__entries_under_their_vrf' => sub {
  my $ssh = fake_ssh();
  my $result = by_vrf($ssh);

  is_deeply [$ssh->commands], [
    'terminal length 0', 'terminal width 0', 'show vrf', 'show ip arp', 'show ipv6 neighbors',
    (map { ("show ip arp vrf $_", "show ipv6 neighbors vrf $_") } qw/blue green grey red/),
    'exit',
  ], 'commands in order';

  is_deeply entries_in($result, ''),
    ['172.20.20.1 92:f9:ea:9d:ae:da', '172.20.20.14 aa:bb:cc:00:01:00'], 'global ARP under the empty VRF';
  my @red = @{ entries_in($result, 'red') };
  my @blue = @{ entries_in($result, 'blue') };
  ok scalar(grep { $_ eq '10.40.0.2 02:00:00:00:04:01' } @red), 'shared 10.40.0.2 in red with its MAC';
  ok scalar(grep { $_ eq '10.40.0.2 02:00:00:00:04:02' } @blue), 'shared 10.40.0.2 in blue with its MAC';
  ok scalar(grep { $_ eq '2001:db8:40::2 02:00:00:00:04:01' } @red), 'shared IPv6 in red';
  ok scalar(grep { $_ eq '2001:db8:40::2 02:00:00:00:04:02' } @blue), 'shared IPv6 in blue';
  is scalar(grep { /^10\.40\.0\.2 / } @red, @blue), 2, 'each shared address appears once per VRF';
  is scalar(grep { /^2001:db8:40::2 / } @red, @blue), 2, 'each shared IPv6 appears once per VRF';
  is_deeply entries_in($result, 'green'), [
    '2001:db8:43::2 02:00:00:00:04:04', '2001:db8:43::ff:fe00:404 02:00:00:00:04:04',
    'fe80::2 02:00:00:00:04:04', 'fe80::5054:ff:fe7d:b87a 52:54:00:7d:b8:7a',
  ], 'green has IPv6 neighbors only';
  is_deeply entries_in($result, 'grey'), [], 'grey has no entries';
  is scalar(@red), 4 + 9, 'red: 4 ARP rows and 9 neighbors';
  is scalar(@blue), 4 + 8, 'blue: 4 ARP rows and 8 neighbors';
  is_deeply [ sort keys %{ $result->{entries}->[0] } ], [qw/ip mac vrf/], 'entry keys';
  is_deeply $result->{vrf_read}, \%LAB_READ, 'every VRF read whole, grey included';
  is $result->{vrf_list_complete}, 1, 'list complete';
  is_deeply $result->{families}, [4, 6], 'both families read';
};

subtest 'arpnip_by_vrf__wrong_name_error__vrf_unread' => sub {
  # the list names a VRF in a case the device then rejects, as the capture's
  # "show ip arp vrf RED" does
  (my $text = fixture_text()) =~ s/^  red( +)/  RED$1/m;
  my $result = by_vrf(fake_ssh(text => $text));
  is $result->{vrf_read}->{RED}, 0, 'RED unread';
  is_deeply entries_in($result, 'RED'), [], 'no entries from the error output';
  is $result->{vrf_read}->{blue}, 1, 'the other VRFs are still whole';
  is_deeply $result->{families}, [4, 6], 'IPv6 works on the device';
  is $result->{vrf_list_complete}, 1, 'the list itself was whole';
};

subtest 'arpnip_by_vrf__ipv6_error_for_one_vrf__that_vrf_unread_keeps_ipv4' => sub {
  my $text = with_output('show ipv6 neighbors vrf blue', "% IPv6 routing table blue does not exist\n");
  my $result = by_vrf(fake_ssh(text => $text));
  is_deeply $result->{vrf_read}, { %LAB_READ, blue => 0 }, 'only blue unread';
  is scalar(@{ entries_in($result, 'blue') }), 4, 'blue IPv4 rows still reported';
  is_deeply $result->{families}, [4, 6], 'IPv6 works on the device';
};

subtest 'arpnip_by_vrf__timeout_on_one_vrf__that_vrf_unread_later_output_ignored' => sub {
  my $ssh = fake_ssh(timeout_on => ['show ip arp vrf green']);
  my $result = by_vrf($ssh);
  is_deeply $result->{vrf_read}, { '' => 1, blue => 1, green => 0, grey => 0, red => 0 },
    'green and everything after it unread';
  is_deeply entries_in($result, 'red'), [], 'red output after the timeout never parsed';
  is_deeply entries_in($result, 'green'), [], 'no partial green rows';
  ok scalar(@{ entries_in($result, 'blue') }), 'blue, read before the timeout, is reported';
  is $result->{vrf_list_complete}, 0, 'list not vouched after a timeout';
  is_deeply [ grep { $_ eq 'show ip arp vrf grey' } $ssh->commands ], [], 'no command after the timeout';
  is_deeply [($ssh->commands)[-1]], ['exit'], 'session closed with exit';
};

subtest 'arpnip_by_vrf__timeout_on_ipv6_of_one_vrf__that_vrf_unread' => sub {
  my $result = by_vrf(fake_ssh(timeout_on => ['show ipv6 neighbors vrf red']));
  is $result->{vrf_read}->{red}, 0, 'red unread';
  is $result->{vrf_read}->{blue}, 1, 'blue, read before it, whole';
  is_deeply $result->{families}, [4, 6], 'the global IPv6 read answered before it';
  is $result->{vrf_list_complete}, 0, 'list not vouched';
};

subtest 'arpnip_by_vrf__timeout_on_global_ipv6__families_ipv4_only_nothing_after' => sub {
  my $ssh = fake_ssh(timeout_on => ['show ipv6 neighbors']);
  my $result = by_vrf($ssh);
  is_deeply $result->{families}, [4], 'IPv6 never answered';
  is_deeply $result->{vrf_read}, { map { ($_ => 0) } keys %LAB_READ }, 'nothing vouched';
  is_deeply [($ssh->commands)[-2,-1]], ['show ipv6 neighbors', 'exit'], 'no command after the timeout';
};

subtest 'arpnip_by_vrf__vrf_list_timeout__returns_undef' => sub {
  my $ssh = fake_ssh(timeout_on => ['show vrf']);
  is by_vrf($ssh), undef, 'failure, so the worker defers';
  is_deeply [$ssh->commands], ['terminal length 0', 'terminal width 0', 'show vrf', 'exit'],
    'stops after the timeout';
};

subtest 'arpnip_by_vrf__vrf_list_error__returns_undef' => sub {
  my $text = with_output('show vrf', "% Invalid input detected at '^' marker.\n");
  is by_vrf(fake_ssh(text => $text)), undef, 'an error in place of the list fails the read';
};

subtest 'arpnip_by_vrf__rows_without_header__returns_undef' => sub {
  my $text = with_output('show vrf', "  red   <not set>   ipv4,ipv6   Et0/1\n");
  is by_vrf(fake_ssh(text => $text)), undef, 'rows with no header line are not trusted';
};

subtest 'arpnip_by_vrf__no_vrfs__global_read_list_complete' => sub {
  foreach my $output ('', "  Name                             Default RD            Protocols   Interfaces\n") {
    my $ssh = fake_ssh(text => with_output('show vrf', $output));
    my $result = by_vrf($ssh);
    is_deeply $result->{vrf_read}, { '' => 1 }, 'the global tables read whole';
    is $result->{vrf_list_complete}, 1, 'an empty list is a whole list';
    is_deeply $result->{families}, [4, 6], 'both families';
    is_deeply [ grep { /vrf/ } $ssh->commands ], ['show vrf'], 'no per-VRF command';
  }
};

subtest 'arpnip_by_vrf__ipv4_only_vrf__vrf_read_whole_no_ipv6_command' => sub {
  (my $text = fixture_text()) =~ s/^(  red +<not set> +)ipv4,ipv6/$1ipv4     /m;
  my $ssh = fake_ssh(text => $text);
  my $result = by_vrf($ssh);
  is_deeply [ grep { /ipv6 neighbors vrf/ } $ssh->commands ],
    [ map { "show ipv6 neighbors vrf $_" } qw/blue green grey/ ], 'no IPv6 command for red';
  is $result->{vrf_read}->{red}, 1, 'red whole on its IPv4 table';
  is_deeply [ grep { /^2001/ } @{ entries_in($result, 'red') } ], [], 'no IPv6 entries for red';
  is_deeply $result->{vrf_read}, \%LAB_READ, 'the others unchanged';
};

subtest 'arpnip_by_vrf__ipv6_unsupported__no_per_vrf_ipv6_command' => sub {
  my $text = with_output('show ipv6 neighbors', "% Invalid input detected at '^' marker.\n");
  my $ssh = fake_ssh(text => $text);
  my $result = by_vrf($ssh);
  is_deeply $result->{families}, [4], 'IPv4 only';
  is_deeply [ grep { /ipv6 neighbors vrf/ } $ssh->commands ], [], 'no per-VRF IPv6 command sent';
  is_deeply $result->{vrf_read}, \%LAB_READ, 'IPv4 reads vouch';
};

subtest 'arpnip_by_vrf__echoed_commands_crlf__same_result' => sub {
  # a real pty echoes each command first and ends lines with CRLF
  (my $text = fixture_text()) =~ s/^#--- (.*)\n/"#--- $1\n$1\n"/mge;
  $text =~ s/^(?!#)(.*)\n/$1\r\n/mg;
  my $plain = by_vrf(fake_ssh());
  my $echoed = by_vrf(fake_ssh(text => $text));
  is_deeply $echoed, $plain, 'identical to the run with no echo';
  is_deeply $echoed->{vrf_read}, \%LAB_READ, 'every table whole despite the echo';
};

subtest 'arpnip_by_vrf__no_prompt__returns_undef' => sub {
  my $ssh = Test::Netdisco::FakeSSH->new(text => "#prompt: iol1\$ \n#--- terminal length 0\n#--- terminal width 0\n#--- exit\n");
  is by_vrf($ssh), undef, 'no [>#] prompt, no session';
};

subtest 'arpnip_by_vrf__ipv6_unsupported__families_ipv4_only' => sub {
  my $text = fixture_text();
  $text =~ s/^(#--- show ipv6 neighbors(?: vrf \w+)?\n).*?(?=^#---)/$1% Invalid input detected at '^' marker.\n/msg;
  my $result = by_vrf(fake_ssh(text => $text));
  is_deeply $result->{families}, [4], 'IPv4 only';
  is_deeply $result->{vrf_read}, \%LAB_READ, 'IPv4 reads still vouch for their VRFs';
  is_deeply entries_in($result, 'green'), [], 'no IPv6 entries from the errors';
  ok scalar(@{ entries_in($result, 'red') }), 'IPv4 entries kept';
};

subtest 'arpnip_by_vrf__unparsed_line__vrf_unread' => sub {
  my $text = with_output('show ip arp vrf blue',
    "Protocol  Address          Age (min)  Hardware Addr   Type   Interface\nsomething unexpected\n");
  my $result = by_vrf(fake_ssh(text => $text));
  is $result->{vrf_read}->{blue}, 0, 'a line that is neither header nor row spoils the read';
  is $result->{vrf_read}->{red}, 1, 'red unaffected';
};

subtest 'arpnip_by_vrf__uppercase_ipv6__stored_lowercase' => sub {
  my $result = by_vrf(fake_ssh());
  my @v6 = grep { $_->{ip} =~ /:/ } @{ $result->{entries} };
  ok scalar(@v6), 'IPv6 entries present';
  is scalar(grep { $_->{ip} ne lc $_->{ip} } @v6), 0, 'all lowercase';
};

subtest 'arpnip_by_vrf__incomplete_arp_row__skipped_and_read_whole' => sub {
  my $text = with_output('show ip arp vrf green',
    "Protocol  Address          Age (min)  Hardware Addr   Type   Interface\n"
    . "Internet  10.43.0.9               0   Incomplete      ARPA\n");
  my $result = by_vrf(fake_ssh(text => $text));
  is_deeply [ grep { /^10\.43/ } @{ entries_in($result, 'green') } ], [], 'incomplete row skipped';
  is $result->{vrf_read}->{green}, 1, 'and the read still whole';
};

subtest 'arpnip_by_vrf__repeated_row__deduped_within_a_vrf' => sub {
  my $row = "Internet  10.45.0.1               0   aabb.cc00.0199  ARPA   Ethernet0/1\n";
  my $text = with_output('show ip arp vrf green',
    "Protocol  Address          Age (min)  Hardware Addr   Type   Interface\n$row$row");
  my $result = by_vrf(fake_ssh(text => $text));
  is scalar(grep { /^10\.45\.0\.1 / } @{ entries_in($result, 'green') }), 1, 'once';
};

subtest 'arpnip__lab_capture__unchanged' => sub {
  my $ssh = fake_ssh();
  my $guard = $ssh->install_expect;
  my @entries = $IOSXE->arpnip('iol1', $ssh, {});

  is_deeply [$ssh->commands], [
    'terminal length 0', 'show ip arp', 'show vrf',
    (map { "show ip arp vrf $_" } qw/blue green grey red/), 'exit',
  ], 'the commands arpnip has always sent';
  is_deeply [ map { "$_->{ip} $_->{mac}" } @entries ], [
    '172.20.20.1 92:f9:ea:9d:ae:da', '172.20.20.14 aa:bb:cc:00:01:00',
    '10.40.0.1 aa:bb:cc:00:01:20', '10.40.0.2 02:00:00:00:04:02',
    '10.42.0.1 aa:bb:cc:00:01:01', '10.42.0.2 02:00:00:00:04:03',
    '10.40.0.1 aa:bb:cc:00:01:10', '10.40.0.2 02:00:00:00:04:01',
    '10.41.0.1 aa:bb:cc:00:01:30', '10.41.0.2 02:00:00:00:04:03',
  ], 'the entries arpnip has always returned';
  is_deeply [ sort keys %{ $entries[0] } ], [qw/ip mac/], 'no vrf key';
};

subtest 'arpnip_by_vrf__through_the_worker__entries_keep_their_vrf' => sub {
  my $ssh = fake_ssh();
  my $guard = $ssh->install_expect;
  my $cli = bless {}, 'IosxeCliStub';
  { no strict 'refs'; *{'IosxeCliStub::arpnip_by_vrf'} = sub { $IOSXE->arpnip_by_vrf('iol1', $ssh, {}) }; }

  delete @{ vars() }{qw/arps vrf_read vrf_read_families vrf_list_complete/};
  vars->{'arps'} = {};
  my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });
  my $status = App::Netdisco::Worker::Plugin::Arpnip::Nodes::gather_arps_by_vrf_cli($device, $cli);
  ok $status->is_ok, 'worker done';

  my @arps = values %{ vars->{'arps'} };
  is scalar(grep { $_->{ip} eq '10.40.0.2' and $_->{vrf} eq 'red' } @arps), 1, '10.40.0.2 in red';
  is scalar(grep { $_->{ip} eq '10.40.0.2' and $_->{vrf} eq 'blue' } @arps), 1, '10.40.0.2 in blue';
  is scalar(grep { $_->{ip} eq '172.20.20.1' and $_->{vrf} eq '' } @arps), 1, 'global under the empty VRF';
  is_deeply vars->{'vrf_read'}, \%LAB_READ, 'vrf_read reaches the worker whole';
  is vars->{'vrf_list_complete'}, 1, 'list complete';
};

done_testing;
