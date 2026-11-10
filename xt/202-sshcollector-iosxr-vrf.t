#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::SSHCollector::Platform::IOSXR;
use App::Netdisco::Worker::Plugin::Arpnip::Nodes ();
use Test::Netdisco::FakeSSH;

use Dancer qw/:moose :script !pass/;

# IOS-XR arpnip_by_vrf against an XRd 26.1.1 lab capture: one command per VRF
# and address family, so a wrong VRF name or a timeout spoils only the reads
# it touches. An empty, misspelled and unknown VRF all print only a timestamp,
# so the device cannot tell them apart and the list is the only source of names.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

my $FIXTURE = 'xt/data/sshcollector/iosxr/router.txt';
my $IOSXR = App::Netdisco::SSHCollector::Platform::IOSXR->new;

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
  return $IOSXR->arpnip_by_vrf('router', $ssh, {});
}

sub entries_in {
  my ($result, $vrf) = @_;
  return [ map { "$_->{ip} $_->{mac}" } grep { $_->{vrf} eq $vrf } @{ $result->{entries} } ];
}

# replace one command's captured output
sub with_output {
  my ($command, $output, $text) = @_;
  $text //= fixture_text();
  $text =~ s/^(#--- \Q$command\E\n).*?(?=^#---)/$1$output/ms or die "no section $command";
  return $text;
}

my $STAMP = "Sat Oct 31 18:19:35.000 UTC\n";
my $ARP_HEADER = "Address         Age        Hardware Addr   State      Type  Interface\n";
my $DASHES = ('-' x 79) . "\n";
sub arp_block {
  my ($location, @rows) = @_;
  return "\n$DASHES$location\n$DASHES$ARP_HEADER" . join '', map { "$_\n" } @rows;
}
my $RED_ROW = '10.60.0.2       00:00:31   0200.0000.0601  Dynamic    ARPA  GigabitEthernet0/0/0/0';

my %LAB_READ = ('' => 1, blue => 1, green => 1, grey => 1, red => 1);

subtest 'arpnip_by_vrf__lab_capture__entries_under_their_vrf' => sub {
  my $ssh = fake_ssh();
  my $result = by_vrf($ssh);

  is_deeply [$ssh->commands], [
    'terminal length 0', 'terminal width 0', 'show vrf all', 'show arp', 'show ipv6 neighbors',
    (map { ("show arp vrf $_", "show ipv6 neighbors vrf $_") } qw/blue green grey red/),
    'exit',
  ], 'commands in order';

  is_deeply entries_in($result, ''), [
    '172.20.20.1 92:f9:ea:9d:ae:da', '172.20.20.19 52:54:00:91:3b:70',
    'fe80::9ef9:eaff:fe9d:aeda 92:f9:ea:9d:ae:da',
  ], 'global tables under the empty VRF';
  my @red = @{ entries_in($result, 'red') };
  my @blue = @{ entries_in($result, 'blue') };
  ok scalar(grep { $_ eq '10.60.0.2 02:00:00:00:06:01' } @red), 'shared 10.60.0.2 in red with its MAC';
  ok scalar(grep { $_ eq '10.60.0.2 02:00:00:00:06:02' } @blue), 'shared 10.60.0.2 in blue with its MAC';
  ok scalar(grep { $_ eq '2001:db8:60::2 02:00:00:00:06:01' } @red), 'shared IPv6 in red';
  ok scalar(grep { $_ eq '2001:db8:60::2 02:00:00:00:06:02' } @blue), 'shared IPv6 in blue';
  is scalar(grep { /^10\.60\.0\.2 / } @red, @blue), 2, 'each shared address appears once per VRF';
  is scalar(grep { /^2001:db8:60::2 / } @red, @blue), 2, 'each shared IPv6 appears once per VRF';
  ok scalar(grep { $_ eq '10.60.0.1 52:54:00:48:04:c0' } @red), 'the router\'s own Interface address is kept';
  is_deeply entries_in($result, 'green'), [
    '2001:db8:63::2 02:00:00:00:06:04', '2001:db8:63::ff:fe00:604 02:00:00:00:06:04',
    'fe80::2 02:00:00:00:06:04',
  ], 'green has IPv6 neighbors only';
  is_deeply entries_in($result, 'grey'), [], 'grey has no entries';
  is scalar(@red), 4 + 5, 'red: 4 ARP rows and 5 neighbors';
  is scalar(@blue), 4 + 7, 'blue: 4 ARP rows and 7 neighbors';
  is_deeply [ sort keys %{ $result->{entries}->[0] } ], [qw/ip mac vrf/], 'entry keys';
  is_deeply $result->{vrf_read}, \%LAB_READ, 'every VRF read whole, grey included';
  is $result->{vrf_list_complete}, 1, 'list complete';
  is_deeply $result->{families}, [4, 6], 'both families read';
};

# the global show ipv6 neighbors also lists VRF neighbors, so only those
# entries are tagged for the worker to treat as possibly another VRF's
subtest 'arpnip_by_vrf__global_ipv6_entries__tagged_mixed_only' => sub {
  my $result = by_vrf(fake_ssh());
  my @global6 = grep { $_->{vrf} eq '' and $_->{ip} =~ /:/ } @{ $result->{entries} };
  my @others = grep { not ($_->{vrf} eq '' and $_->{ip} =~ /:/) } @{ $result->{entries} };
  ok scalar(@global6), 'the capture has global IPv6 entries';
  is scalar(grep { not $_->{mixed} } @global6), 0, 'every global IPv6 entry is tagged mixed';
  is scalar(grep { exists $_->{mixed} } @others), 0, 'no global IPv4 or VRF entry is tagged';
};

subtest 'arpnip_by_vrf__mcast_adjacency__skipped_vrf_whole' => sub {
  my $result = by_vrf(fake_ssh());
  is scalar(grep { $_->{ip} =~ /Mcast/ } @{ $result->{entries} }), 0, 'no multicast adjacency entry';
  is $result->{vrf_read}->{red}, 1, 'red whole despite its adjacency rows';

  my $row = '[Mcast adjacency]                           - 0200.0000.0601 REACH Gi0/0/0/0            0/RP0/CPU0     ';
  my $text = with_output('show ipv6 neighbors vrf grey', "$STAMP$row\n");
  is by_vrf(fake_ssh(text => $text))->{vrf_read}->{grey}, 0, 'one with a real MAC is not the known non-row';
};

subtest 'arpnip_by_vrf__two_locations__both_blocks_parsed' => sub {
  my $second = '10.60.0.9       00:00:11   0200.0000.0699  Dynamic    ARPA  GigabitEthernet0/1/0/0';
  my $text = with_output('show arp vrf red',
    $STAMP . arp_block('0/RP0/CPU0', $RED_ROW) . arp_block('0/1/CPU0', $second));
  my $result = by_vrf(fake_ssh(text => $text));
  ok scalar(grep { $_ eq '10.60.0.2 02:00:00:00:06:01' } @{ entries_in($result, 'red') }), 'first block';
  ok scalar(grep { $_ eq '10.60.0.9 02:00:00:00:06:99' } @{ entries_in($result, 'red') }), 'second block';
  is $result->{vrf_read}->{red}, 1, 'red whole';
};

subtest 'arpnip_by_vrf__unknown_line__vrf_unread' => sub {
  my $text = with_output('show arp vrf blue', $STAMP . arp_block('0/RP0/CPU0', $RED_ROW, 'something unexpected'));
  my $result = by_vrf(fake_ssh(text => $text));
  is $result->{vrf_read}->{blue}, 0, 'a line that is no known form spoils the read';
  is $result->{vrf_read}->{red}, 1, 'red unaffected';
  is_deeply $result->{families}, [4, 6], 'IPv6 still works';
};

subtest 'arpnip_by_vrf__arp_error__vrf_unread' => sub {
  my $text = with_output('show arp vrf blue', "$STAMP% Invalid input detected at '^' marker.\n");
  my $result = by_vrf(fake_ssh(text => $text));
  is $result->{vrf_read}->{blue}, 0, 'blue unread';
  is_deeply $result->{vrf_read}, { %LAB_READ, blue => 0 }, 'only blue';
};

subtest 'arpnip_by_vrf__invalid_vrf_ipv6__ipv6_unread' => sub {
  # a VRF the list names but IPv6 rejects, as the capture's nosuchvrf is
  (my $text = fixture_text()) =~ s/^(blue .*\n)/$1nosuchvrf            not set\n/m or die 'fixture changed';
  my $ssh = fake_ssh(text => $text);
  my $result = by_vrf($ssh);
  is $result->{vrf_read}->{nosuchvrf}, 0, 'unread though its IPv4 table was empty and whole';
  is_deeply $result->{vrf_read}, { %LAB_READ, nosuchvrf => 0 }, 'the others whole';
  is_deeply $result->{families}, [4, 6], 'IPv6 works on the device';
  is $result->{vrf_list_complete}, 1, 'the list itself was whole';
  ok scalar(grep { $_ eq 'show ipv6 neighbors vrf nosuchvrf' } $ssh->commands), 'the command was sent';
};

subtest 'arpnip_by_vrf__no_ipv6__families_ipv4_only_no_vrf_ipv6_commands' => sub {
  foreach my $reply ("% Invalid input detected at '^' marker.\n", "Invalid VRF specified, please check vrf name.\n") {
    my $ssh = fake_ssh(text => with_output('show ipv6 neighbors', "$STAMP$reply"));
    my $result = by_vrf($ssh);
    is_deeply $result->{families}, [4], 'IPv4 only';
    is_deeply [ grep { /ipv6 neighbors vrf/ } $ssh->commands ], [], 'no per-VRF IPv6 command sent';
    is_deeply $result->{vrf_read}, \%LAB_READ, 'IPv4 reads vouch';
    is_deeply entries_in($result, 'green'), [], 'no IPv6 entries';
  }
};

subtest 'arpnip_by_vrf__timeout_on_one_vrf__that_vrf_unread_later_output_ignored' => sub {
  my $ssh = fake_ssh(timeout_on => ['show arp vrf green']);
  my $result = by_vrf($ssh);
  is_deeply $result->{vrf_read}, { '' => 1, blue => 1, green => 0, grey => 0, red => 0 },
    'green and everything after it unread';
  is_deeply entries_in($result, 'red'), [], 'red output after the timeout never parsed';
  is_deeply entries_in($result, 'green'), [], 'no partial green rows';
  ok scalar(@{ entries_in($result, 'blue') }), 'blue, read before the timeout, is reported';
  is $result->{vrf_list_complete}, 0, 'list not vouched after a timeout';
  is_deeply [ grep { $_ eq 'show arp vrf grey' } $ssh->commands ], [], 'no command after the timeout';
  is_deeply [($ssh->commands)[-1]], ['exit'], 'session closed with exit';
};

subtest 'arpnip_by_vrf__timeout_on_global_ipv6__families_ipv4_only_nothing_after' => sub {
  my $ssh = fake_ssh(timeout_on => ['show ipv6 neighbors']);
  my $result = by_vrf($ssh);
  is_deeply $result->{families}, [4], 'IPv6 never answered';
  is_deeply $result->{vrf_read}, { map { ($_ => 0) } keys %LAB_READ }, 'nothing vouched';
  is_deeply [($ssh->commands)[-2,-1]], ['show ipv6 neighbors', 'exit'], 'no command after the timeout';
};

subtest 'arpnip_by_vrf__vrf_list_timeout__returns_undef' => sub {
  my $ssh = fake_ssh(timeout_on => ['show vrf all']);
  is by_vrf($ssh), undef, 'failure, so the worker defers';
  is_deeply [$ssh->commands], ['terminal length 0', 'terminal width 0', 'show vrf all', 'exit'],
    'stops after the timeout';
};

subtest 'arpnip_by_vrf__vrf_list_not_a_list__returns_undef' => sub {
  my $text = with_output('show vrf all', "$STAMP% Invalid input detected at '^' marker.\n");
  is by_vrf(fake_ssh(text => $text)), undef, 'an error in place of the list';
  $text = with_output('show vrf all', "${STAMP}red                  not set\n");
  is by_vrf(fake_ssh(text => $text)), undef, 'rows with no header are not trusted';
  is by_vrf(fake_ssh(text => with_output('show vrf all', $STAMP))), undef, 'a timestamp alone is no list';
};

subtest 'arpnip_by_vrf__header_only_list__whole_empty_list' => sub {
  my $header = "VRF                  RD                  RT                         AFI   SAFI     \n";
  my $ssh = fake_ssh(text => with_output('show vrf all', "$STAMP$header"));
  my $result = by_vrf($ssh);
  is_deeply $result->{vrf_read}, { '' => 1 }, 'the global tables read whole';
  is $result->{vrf_list_complete}, 1, 'an empty list is a whole list';
  is_deeply $result->{families}, [4, 6], 'both families';
  is_deeply [ grep { /vrf/ } $ssh->commands ], ['show vrf all'], 'no per-VRF command';
};

subtest 'arpnip_by_vrf__rt_continuation_lines__names_still_read' => sub {
  my $text = with_output('show vrf all', $STAMP
    . "VRF                  RD                  RT                         AFI   SAFI     \n"
    . "red                  100:1               100:1                      IPV4  Unicast  \n"
    . "                                         100:2                      IPV4  Unicast  \n"
    . "blue                 not set            \n");
  my $result = by_vrf(fake_ssh(text => $text));
  is_deeply $result->{vrf_read}, { '' => 1, blue => 1, red => 1 }, 'only the two rows are VRFs';
  is $result->{vrf_list_complete}, 1, 'list complete';
};

subtest 'arpnip_by_vrf__vrf_named_Default__listed_and_read' => sub {
  foreach my $name (qw/Default DEFAULT/) {
    my $text = with_output('show vrf all', $STAMP
      . "VRF                  RD                  RT                         AFI   SAFI     \n"
      . "$name              not set            \n")
      . "#--- show arp vrf $name\n$STAMP#--- show ipv6 neighbors vrf $name\n$STAMP";
    my $ssh = fake_ssh(text => $text);
    my $result = by_vrf($ssh);
    is $result->{vrf_read}->{$name}, 1, "[$name] read whole";
    ok scalar(grep { $_ eq "show arp vrf $name" } $ssh->commands), "[$name] queried";
    is $result->{vrf_list_complete}, 1, 'list complete';
  }
};

subtest 'arpnip_by_vrf__unparseable_list_row__list_incomplete_named_vrfs_read' => sub {
  foreach my $row ("   continuation with no row above\n", "lonelyname\n") {
    my $text = with_output('show vrf all', $STAMP
      . "VRF                  RD                  RT                         AFI   SAFI     \n"
      . $row . "red                  not set            \n");
    my $result = by_vrf(fake_ssh(text => $text));
    is $result->{vrf_list_complete}, 0, 'list incomplete';
    is $result->{vrf_read}->{red}, 1, 'the named VRF is still read';
  }
};

subtest 'arpnip_by_vrf__unusable_vrf_name__unread_without_a_command' => sub {
  # replies that would read whole, so only the guard keeps these at 0
  my $extra = join '', map { "#--- show arp vrf $_\n$STAMP#--- show ipv6 neighbors vrf $_\n$STAMP" }
    ("r\x{e9}d", 'bad;name', 'ALL', 'all');
  foreach my $name ("r\x{e9}d", 'bad;name', 'ALL', 'all') {
    my $text = with_output('show vrf all', $STAMP
      . "VRF                  RD                  RT                         AFI   SAFI     \n"
      . "red                  not set            \n$name                  not set            \n") . $extra;
    my $ssh = fake_ssh(text => $text);
    my $result = by_vrf($ssh);
    is $result->{vrf_read}->{$name}, 0, "[$name] reported 0";
    is scalar(grep { /^show (?:arp|ipv6 neighbors) vrf \Q$name\E$/ } $ssh->commands), 0, 'no command for it';
    is $result->{vrf_read}->{red}, 1, 'red whole';
  }
};

subtest 'arpnip_by_vrf__echoed_commands_crlf__parsed' => sub {
  # a real pty echoes each command first and ends lines with CRLF
  (my $text = fixture_text()) =~ s/^#--- (.*)\n/"#--- $1\n$1\n"/mge;
  $text =~ s/^(?!#)(.*)\n/$1\r\n/mg;
  my $plain = by_vrf(fake_ssh());
  my $echoed = by_vrf(fake_ssh(text => $text));
  is_deeply $echoed, $plain, 'identical to the run with no echo';
  is_deeply $echoed->{vrf_read}, \%LAB_READ, 'every table whole despite the echo';
};

subtest 'arpnip_by_vrf__hash_only_banner_before_prompt__not_taken_as_prompt' => sub {
  # the banner arrives in a read of its own, and the real prompt after it
  my $ssh = fake_ssh();
  my $guard = $ssh->install_expect;
  no warnings qw/redefine once/;
  my $new = \&Test::Netdisco::FakeSSH::Expect::new;
  local *Test::Netdisco::FakeSSH::Expect::new = sub {
    my $self = $new->(@_);
    ($self->{late}, $self->{buffer}) = ($self->{buffer}, "####\r\n");
    return $self;
  };
  local *Test::Netdisco::FakeSSH::Expect::expect = sub {
    my ($self, $timeout, @patterns) = @_;
    my ($regex) = grep { ref $_ eq 'Regexp' } @patterns;
    # a pty is read as it arrives, so the first prompt wins, not the last
    while (1) {
      my $buffer = $self->{buffer};
      foreach my $end (grep { substr($buffer, $_ - 1, 1) =~ m/[#>\n]/ } 1 .. length $buffer) {
        my $seen = substr $buffer, 0, $end;
        next unless $seen =~ $regex;
        ($self->{before}, $self->{match}, $self->{after}) = ($`, $&, $');
        $self->{buffer} = substr $buffer, $end;
        return (1, undef, $&, $`, $');
      }
      return (undef, '1:TIMEOUT', undef, $buffer, '') unless exists $self->{late};
      $self->{buffer} .= delete $self->{late};
    }
  };
  my $result = $IOSXR->arpnip_by_vrf('router', $ssh, {});
  ok $result, 'a result, not a deferral';
  is_deeply $result->{vrf_read}, \%LAB_READ, 'every table read whole';
  is_deeply [ ($ssh->commands)[0, 1, 2] ], ['terminal length 0', 'terminal width 0', 'show vrf all'], 'commands in step';
};

subtest 'arpnip_by_vrf__no_prompt__returns_undef' => sub {
  my $ssh = Test::Netdisco::FakeSSH->new(text => "#prompt: router\$ \n#--- terminal length 0\n#--- terminal width 0\n#--- exit\n");
  is by_vrf($ssh), undef, 'no # prompt, no session';
};

subtest 'arpnip_by_vrf__failed_command__logged_at_debug_with_the_command' => sub {
  my @logged;
  no warnings qw/redefine once/;
  local *App::Netdisco::SSHCollector::Platform::IOSXR::debug = sub { push @logged, @_ };
  by_vrf(fake_ssh(timeout_on => ['show arp vrf green']));
  ok scalar(grep { /\[show arp vrf green\] failed/ } @logged), 'timeout names the command';
  @logged = ();
  by_vrf(fake_ssh(text => with_output('show arp vrf blue', "$STAMP% Invalid input\n")));
  ok scalar(grep { /\[show arp vrf blue\] returned an error/ } @logged), 'error names the command';
};

subtest 'arpnip__lab_capture__unchanged' => sub {
  # today's prompt pattern wants a space after the "#"
  (my $text = fixture_text()) =~ s/^(#prompt: .*#)$/$1 /m or die 'fixture changed';
  my $ssh = Test::Netdisco::FakeSSH->new(text => $text);
  my $guard = $ssh->install_expect;
  my @entries = do {
    local $SIG{__WARN__} = sub {}; # arpnip splits blank lines into undef fields
    $IOSXR->arpnip('router', $ssh, {});
  };

  is_deeply [$ssh->commands], ['terminal length 0', 'show arp vrf all', 'exit'],
    'the commands arpnip has always sent';
  is_deeply [ map { "$_->{ip} $_->{mac}" } @entries ], [
    '10.60.0.1 5254.0048.04c0', '10.60.0.1 5254.00fc.fa99',
    '10.60.0.2 0200.0000.0601', '10.60.0.2 0200.0000.0602',
    '10.61.0.1 5254.0018.1b0c', '10.61.0.2 0200.0000.0603',
    '10.62.0.1 5254.0046.10e6', '10.62.0.2 0200.0000.0603',
  ], 'the entries arpnip has always returned, in the device format';
  is_deeply [ sort keys %{ $entries[0] } ], [qw/ip mac/], 'no vrf key';
};

subtest 'arpnip_by_vrf__through_the_worker__entries_keep_their_vrf' => sub {
  my $ssh = fake_ssh();
  my $cli = bless {}, 'IosxrCliStub';
  { no strict 'refs'; *{'IosxrCliStub::arpnip_by_vrf'} = sub { by_vrf($ssh) }; }

  delete @{ vars() }{qw/arps vrf_read vrf_read_families vrf_list_complete/};
  vars->{'arps'} = {};
  my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });
  my $status = App::Netdisco::Worker::Plugin::Arpnip::Nodes::gather_arps_by_vrf_cli($device, $cli);
  ok $status->is_ok, 'worker done';

  my @arps = values %{ vars->{'arps'} };
  is scalar(grep { $_->{ip} eq '10.60.0.2' and $_->{vrf} eq 'red' } @arps), 1, '10.60.0.2 in red';
  is scalar(grep { $_->{ip} eq '10.60.0.2' and $_->{vrf} eq 'blue' } @arps), 1, '10.60.0.2 in blue';
  is scalar(grep { $_->{ip} eq '172.20.20.1' and $_->{vrf} eq '' } @arps), 1, 'global under the empty VRF';
  is_deeply vars->{'vrf_read'}, \%LAB_READ, 'vrf_read reaches the worker whole';
  is vars->{'vrf_list_complete'}, 1, 'list complete';
};

# a session that cannot open its pty, as Net::OpenSSH reports a failed spawn
{
  package NoPtySSH;
  our @ISA = ('Test::Netdisco::FakeSSH');
  sub open2pty { my $self = shift; $self->{error} = 'spawn failed'; return () }
  sub error { return $_[0]{error} }
}

subtest 'arpnip_by_vrf__pty_not_opened__warns_and_returns_undef' => sub {
  my @warned;
  local $SIG{__WARN__} = sub { push @warned, join '', @_ };
  my $ssh = NoPtySSH->new(text => fixture_text());
  my $guard = $ssh->install_expect;
  is $IOSXR->arpnip_by_vrf('router', $ssh, {}), undef, 'no pty, no result, so the worker defers';
  is_deeply [$ssh->commands], [], 'nothing sent';
  is scalar(@warned), 1, 'one warning';
  like $warned[0] // '', qr/unable to run remote command \[router\] spawn failed/, 'names the host and the error';
};

foreach my $command ('terminal length 0', 'terminal width 0') {
  subtest "arpnip_by_vrf__${\ join '_', split / /, $command}_times_out__returns_undef_logs_info" => sub {
    my @logged;
    no warnings 'redefine';
    local *App::Netdisco::SSHCollector::Platform::IOSXR::info = sub { push @logged, join '', @_ };
    my $ssh = fake_ssh(timeout_on => [$command]);
    is by_vrf($ssh), undef, 'no session, so the worker defers';
    is +($ssh->commands)[-1], $command, 'nothing sent after the timed-out command';
    is scalar(grep { m/arpnip_by_vrf\(\) unable to reach CLI prompt/ } @logged), 1, 'the skip is logged at info';
  };
}

subtest 'arpnip_by_vrf__timeout_argument__used_for_every_expect_default_30' => sub {
  my @timeouts;
  my $original = \&Test::Netdisco::FakeSSH::Expect::expect;
  no warnings 'redefine';
  local *Test::Netdisco::FakeSSH::Expect::expect = sub { push @timeouts, $_[1]; goto &$original };
  my $ssh = fake_ssh();
  my $guard = $ssh->install_expect;
  ok ref $IOSXR->arpnip_by_vrf('router', $ssh, { timeout => 7 }) eq 'HASH', 'read with a timeout argument';
  ok scalar(@timeouts), 'expect was called';
  is_deeply [ grep { $_ != 7 } @timeouts ], [], 'every expect waits the configured 7 s';
  @timeouts = ();
  ok ref $IOSXR->arpnip_by_vrf('router', fake_ssh(), undef) eq 'HASH', 'read with no arguments at all';
  is_deeply [ grep { $_ != 30 } @timeouts ], [], 'every expect waits the default 30 s';
};

done_testing;
