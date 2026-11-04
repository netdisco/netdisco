#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::SSHCollector::Platform::NXOS;
use App::Netdisco::Worker::Plugin::Arpnip::Nodes ();
use Test::Netdisco::FakeSSH;

use Dancer qw/:moose :script !pass/;

# NX-OS arpnip_by_vrf against a 9300v lab capture: the VRF list, then the
# per-VRF commands chained into a few exec requests. Each document is
# assigned by its own VRF and shape and judged whole on its own count, so a
# bad name or a missing document spoils only the reads it touches; a failed
# request or undecodable fragment spoils the rest of its request.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

my @LISTED = qw/blue default egress-loadbalance-resolution- green grey management red/;
my $FIXTURE = 'xt/data/sshcollector/nxos/nxos9300v.txt';
my $CHAIN_FIXTURE = 'xt/data/sshcollector/nxos/nxos9300v-chain.txt';
my $TEXT_FIXTURE = 'xt/data/sshcollector/nxos/nxos9300v-text.txt';
my $NXOS = App::Netdisco::SSHCollector::Platform::NXOS->new;

sub slurp { my $path = shift; local (@ARGV, $/) = ($path); return scalar <> }

sub fake_ssh {
  my (%opts) = @_;
  my $ssh = Test::Netdisco::FakeSSH->new(text => ($opts{text} // slurp($FIXTURE)));
  $ssh->timeout_on($_) for @{ $opts{timeout_on} || [] };
  return $ssh;
}

sub by_vrf { return $NXOS->arpnip_by_vrf('switch', $_[0], {}) }

sub entries_in {
  my ($result, $vrf) = @_;
  return [ map { "$_->{ip} $_->{mac}" } grep { $_->{vrf} eq $vrf } @{ $result->{entries} } ];
}

# replace one command's captured output
sub with_output {
  my ($command, $output) = @_;
  (my $text = slurp($FIXTURE)) =~ s/^(#--- \Q$command\E\n).*?(?=^#---|\z)/$1$output/ms
    or die "no section $command";
  return $text;
}

# the chained command for names, as the collector sends it: ARP then neighbor each
sub chain_of { return join ' ; ', map { (arp($_), nd($_)) } @_ }

# the per-VRF commands are sent in these chained requests (640 bytes each)
sub lab_requests { return (chain_of(@LISTED[0 .. 5]), chain_of($LISTED[6])) }

# the exec requests after the VRF list
sub chains_sent { my $ssh = shift; return [ grep { $_ ne 'show vrf | json' } $ssh->commands ] }

# the chain fixture with the documents of each request (or only request $only)
# passed through $change (a list in, a list out)
sub chain_with {
  my ($change, $only) = @_;
  my @commands = lab_requests();
  my $text = slurp($CHAIN_FIXTURE);
  foreach my $index (0 .. $#commands) {
    next if defined $only and $only != $index;
    $text =~ s{^(#--- \Q$commands[$index]\E\n)(.*?)(?=^#---|\z)}{
      my ($head, @docs) = ($1, split /\n/, $2); $head . join('', map { "$_\n" } $change->(@docs)) }mse
      or die 'chain fixture changed';
  }
  return $text;
}

# synthetic: default plus v1..v8, each an empty table in both families, for
# lists that need more than one chained request
sub many_vrf_text {
  my @names = @_ ? @_ : ('default', map { "v$_" } 1 .. 8);
  my $list = join ', ', map { qq({"vrf_name": "$_"}) } @names;
  my $text = with_output('show vrf | json', qq({"TABLE_vrf": {"ROW_vrf": [$list]}}\n));
  foreach my $name (@names) {
    $text .= "#--- " . arp($name) . "\n"
      . qq({"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "$name", "cnt-total": "0"}}}\n)
      . "#--- " . nd($name) . "\n"
      . qq({"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "$name", "TABLE_afi": {"ROW_afi": {"afi": "ipv6", "count": "0"}}}}}\n);
  }
  return ($text, @names);
}

sub arp { return "show ip arp vrf $_[0] | json | no-more" }
sub nd  { return "show ipv6 neighbor vrf $_[0] | json | no-more" }

my %LAB_READ = ('' => 1, blue => 1, 'egress-loadbalance-resolution-' => 1,
                green => 1, grey => 1, management => 1, red => 1);

subtest 'arpnip_by_vrf__lab_capture__entries_under_their_vrf' => sub {
  my $ssh = fake_ssh();
  my $result = by_vrf($ssh);

  is_deeply [$ssh->commands], [ 'show vrf | json', lab_requests() ],
    'the list, then the per-VRF commands chained into two exec requests';

  my @red = @{ entries_in($result, 'red') };
  my @blue = @{ entries_in($result, 'blue') };
  ok scalar(grep { $_ eq '10.10.10.2 02:00:00:00:02:01' } @red), '10.10.10.2 in red with its MAC';
  ok scalar(grep { $_ eq '10.10.10.2 02:00:00:00:02:02' } @blue), '10.10.10.2 in blue with its MAC';
  ok scalar(grep { $_ eq '2001:db8:10::2 02:00:00:00:02:01' } @red), 'shared IPv6 in red';
  ok scalar(grep { $_ eq '2001:db8:10::2 02:00:00:00:02:02' } @blue), 'shared IPv6 in blue';
  is scalar(grep { /^10\.10\.10\.2 / } @red, @blue), 2, 'the shared address once per VRF';
  is scalar(grep { /^2001:db8:10::2 / } @red, @blue), 2, 'the shared IPv6 once per VRF';
  is scalar(grep { /^fe80::2 / } @red), 2, 'link-local neighbors kept, one per MAC';
  is_deeply entries_in($result, 'green'), [
    '2001:db8:13::2 02:00:00:00:02:04', '2001:db8:13::ff:fe00:204 02:00:00:00:02:04',
    'fe80::2 02:00:00:00:02:04',
  ], 'green has IPv6 neighbors only';
  is_deeply entries_in($result, 'grey'), [], 'grey has no entries';
  is $result->{vrf_read}->{grey}, 1, 'and is read whole';
  is_deeply entries_in($result, ''), [], 'default holds none';
  is_deeply entries_in($result, 'management'), ['172.20.20.1 92:f9:ea:9d:ae:da'], 'management named';
  is scalar(@red), 2 + 6, 'red: 2 ARP rows and 6 neighbors';
  is scalar(@blue), 2 + 7, 'blue: 2 ARP rows and 7 neighbors';
  is_deeply [ sort keys %{ $result->{entries}->[0] } ], [qw/ip mac vrf/], 'entry keys';
  is_deeply $result->{vrf_read}, \%LAB_READ, 'every VRF read whole, default under the empty name';
  is $result->{vrf_list_complete}, 1, 'list complete';
  is_deeply $result->{families}, [4, 6], 'both families read';
};

subtest 'arpnip_by_vrf__single_row_as_hash__parsed' => sub {
  my $result = by_vrf(fake_ssh());
  is_deeply entries_in($result, 'management'), ['172.20.20.1 92:f9:ea:9d:ae:da'],
    'one ROW_adj hash is one entry';

  my $list = '{"TABLE_vrf": {"ROW_vrf": {"vrf_name": "default", "vrf_id": "1"}}}';
  my $text = with_output('show vrf | json', "$list\n");
  $text =~ s/^#--- (?!show vrf|show (?:ip arp|ipv6 neighbor) vrf default).*?(?=^#---|\z)//msg;
  my $one = by_vrf(fake_ssh(text => $text));
  is_deeply $one->{vrf_read}, { '' => 1 }, 'one listed VRF as a hash';
};

subtest 'arpnip_by_vrf__unknown_name_empty_reply__vrf_unread' => sub {
  my $text = with_output('show vrf | json',
    '{"TABLE_vrf": {"ROW_vrf": [{"vrf_name": "red"}, {"vrf_name": "default"}, {"vrf_name": "nosuchvrf"}]}}' . "\n");
  $text .= "#--- " . nd('nosuchvrf') . "\n";
  my $result = by_vrf(fake_ssh(text => $text));
  is $result->{vrf_read}->{nosuchvrf}, 0, 'empty output is unread, not empty';
  is_deeply entries_in($result, 'nosuchvrf'), [], 'no entries';
  is $result->{vrf_read}->{red}, 1, 'red still whole';
  is $result->{vrf_list_complete}, 1, 'the list itself was whole';
};

subtest 'arpnip_by_vrf__count_mismatch__vrf_unread' => sub {
  (my $fewer = slurp($FIXTURE)) =~ s/("vrf-name-out": "red", "cnt-total": )"2"/$1"3"/
    or die 'fixture changed';
  my $result = by_vrf(fake_ssh(text => $fewer));
  is $result->{vrf_read}->{red}, 0, 'ARP count above the rows: red unread';
  is scalar(@{ entries_in($result, 'red') }), 2 + 6, 'rows read are still reported';
  is $result->{vrf_read}->{blue}, 1, 'blue whole';

  (my $v6 = slurp($FIXTURE)) =~ s/("vrf-name-out": "blue", "TABLE_afi": \{"ROW_afi": \{"afi": "ipv6", "count": )"7"/$1"8"/
    or die 'fixture changed';
  is by_vrf(fake_ssh(text => $v6))->{vrf_read}->{blue}, 0, 'IPv6 count above the rows: blue unread';

  (my $under = slurp($FIXTURE)) =~ s/("vrf-name-out": "green", "cnt-total": )"0"/$1"2"/
    or die 'fixture changed';
  is by_vrf(fake_ssh(text => $under))->{vrf_read}->{green}, 0, 'count with no rows: unread';
};

subtest 'arpnip_by_vrf__undecodable_ipv6__vrf_unread_ipv4_rows_kept' => sub {
  my $text = with_output(nd('red'), "{\"TABLE_vrf\": {\"ROW_vrf\": {\"vrf-na\n");
  my $result = by_vrf(fake_ssh(text => $text));
  is $result->{vrf_read}->{red}, 0, 'red unread';
  is_deeply entries_in($result, 'red'),
    ['10.10.10.2 02:00:00:00:02:01', '10.11.0.2 02:00:00:00:02:03'], 'IPv4 rows kept';
  is $result->{vrf_read}->{blue}, 1, 'blue whole';
  is_deeply $result->{families}, [4, 6], 'families unchanged';
};

subtest 'arpnip_by_vrf__reply_names_other_vrf__vrf_unread' => sub {
  (my $text = slurp($FIXTURE)) =~ s/"vrf-name-out": "blue"/"vrf-name-out": "red"/
    or die 'fixture changed';
  my $result = by_vrf(fake_ssh(text => $text));
  is $result->{vrf_read}->{blue}, 0, 'blue unread when its reply names red';
  is $result->{vrf_read}->{red}, 1, 'red whole: the stray document is in a request that did not ask for red';
  is scalar(grep { /^10\./ } @{ entries_in($result, 'blue') }), 0, 'blue takes no ARP rows';
  is scalar(grep { /^10\./ } @{ entries_in($result, 'red') }), 2, 'red keeps its own two';
  is $result->{vrf_read}->{green}, 1, 'green whole';

  (my $cased = slurp($FIXTURE)) =~ s/"vrf-name-out": "green"/"vrf-name-out": "GREEN"/g;
  my $same = by_vrf(fake_ssh(text => $cased));
  is $same->{vrf_read}->{green}, 1, 'case differences are the same VRF';
  ok !exists $same->{vrf_read}->{GREEN}, 'the listed name is used';
};

subtest 'arpnip_by_vrf__incomplete_row__skipped_and_counted' => sub {
  my $text = with_output(arp('green'),
    '{"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "green", "cnt-total": "2", "TABLE_adj": {"ROW_adj": ['
    . '{"intf-out": "Ethernet1/5", "ip-addr-out": "10.13.0.9", "time-stamp": "PT1S", "mac": "INCOMPLETE", "flags": null}, '
    . '{"intf-out": "Ethernet1/5", "ip-addr-out": "10.13.0.2", "time-stamp": "PT1S", "mac": "0200.0000.0204", "flags": null}'
    . ']}}}}' . "\n");
  my $result = by_vrf(fake_ssh(text => $text));
  ok !scalar(grep { /^10\.13\.0\.9 / } @{ entries_in($result, 'green') }), 'INCOMPLETE row skipped';
  ok scalar(grep { /^10\.13\.0\.2 / } @{ entries_in($result, 'green') }), 'the other row kept';
  is $result->{vrf_read}->{green}, 1, 'counted in cnt-total, so green is whole';
};

subtest 'arpnip_by_vrf__repeated_row__deduped_within_a_vrf' => sub {
  my $row = '{"intf-out": "Ethernet1/5", "ip-addr-out": "10.13.0.2", "mac": "0200.0000.0204"}';
  my $text = with_output(arp('green'),
    qq({"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "green", "cnt-total": "2", "TABLE_adj": {"ROW_adj": [$row, $row]}}}}\n));
  my $result = by_vrf(fake_ssh(text => $text));
  is scalar(grep { /^10\.13\.0\.2 / } @{ entries_in($result, 'green') }), 1, 'once';
  is $result->{vrf_read}->{green}, 1, 'still whole';
};

subtest 'arpnip_by_vrf__uppercase_ipv6__lowercased' => sub {
  (my $text = slurp($FIXTURE)) =~ s/2001:db8:13::2"/2001:DB8:13::2"/ or die 'fixture changed';
  my $result = by_vrf(fake_ssh(text => $text));
  ok scalar(grep { $_ eq '2001:db8:13::2 02:00:00:00:02:04' } @{ entries_in($result, 'green') }), 'lowercase';
};

subtest 'arpnip_by_vrf__vrf_list_fails__returns_undef' => sub {
  is by_vrf(fake_ssh(timeout_on => ['show vrf | json'])), undef, 'capture error';
  is by_vrf(fake_ssh(text => with_output('show vrf | json', "{not json\n"))), undef, 'undecodable';
  is by_vrf(fake_ssh(text => with_output('show vrf | json', "{\"TABLE_vrf\": {}}\n"))), undef, 'no rows';
  is by_vrf(fake_ssh(text => with_output('show vrf | json', "\n"))), undef, 'empty output';
};

subtest 'arpnip_by_vrf__unnamable_vrf_row__list_incomplete' => sub {
  foreach my $rows ('{"vrf_id": "9"}', '"junk"', '{"vrf_name": ""}') {
    my $text = with_output('show vrf | json',
      qq({"TABLE_vrf": {"ROW_vrf": [{"vrf_name": "red"}, $rows]}}\n));
    my $result = by_vrf(fake_ssh(text => $text));
    is $result->{vrf_list_complete}, 0, "list incomplete with row $rows";
    is $result->{vrf_read}->{red}, 1, 'the named VRF is still read';
  }
};

subtest 'arpnip_by_vrf__list_without_default__global_read_list_incomplete' => sub {
  my $text = with_output('show vrf | json',
    '{"TABLE_vrf": {"ROW_vrf": [{"vrf_name": "red"}, {"vrf_name": "blue"}]}}' . "\n");
  my $ssh = fake_ssh(text => $text);
  my $result = by_vrf($ssh);
  is_deeply $result->{vrf_read}, { '' => 1, red => 1, blue => 1 }, 'the global table is read and reported';
  is $result->{vrf_list_complete}, 0, 'a list that omits default is not vouched';
  ok scalar(grep { index($_, arp('default')) >= 0 } $ssh->commands), 'show ip arp vrf default was sent';
};

subtest 'arpnip_by_vrf__list_with_default__list_complete' => sub {
  my $text = with_output('show vrf | json',
    '{"TABLE_vrf": {"ROW_vrf": [{"vrf_name": "red"}, {"vrf_name": "default"}]}}' . "\n");
  my $result = by_vrf(fake_ssh(text => $text));
  is_deeply $result->{vrf_read}, { '' => 1, red => 1 }, 'default read once, as the empty name';
  is $result->{vrf_list_complete}, 1, 'list complete';
};

subtest 'arpnip_by_vrf__afi_not_ipv6__vrf_unread' => sub {
  (my $text = slurp($FIXTURE)) =~ s/"afi": "ipv6", "count": "3"/"afi": "ipv4", "count": "3"/
    or die 'fixture changed';
  my $result = by_vrf(fake_ssh(text => $text));
  is $result->{vrf_read}->{green}, 0, 'green unread';
  is scalar(@{ entries_in($result, 'green') }), 0, 'no rows stored as IPv6';
};

subtest 'arpnip_by_vrf__non_ascii_vrf_name__unread_without_a_command' => sub {
  my $text = with_output('show vrf | json',
    qq({"TABLE_vrf": {"ROW_vrf": [{"vrf_name": "red"}, {"vrf_name": "r\\u00e9d"}]}}\n));
  my $ssh = fake_ssh(text => $text);
  my $result = by_vrf($ssh);
  is $result->{vrf_read}->{"r\x{e9}d"}, 0, 'unread';
  is scalar(grep { /r.d/ and !/red/ } $ssh->commands), 0, 'never sent';
};

subtest 'arpnip_by_vrf__vrf_named_all__unread_without_a_command' => sub {
  my $text = with_output('show vrf | json',
    '{"TABLE_vrf": {"ROW_vrf": [{"vrf_name": "red"}, {"vrf_name": "ALL"}]}}' . "\n");
  # replies that would read whole, so only the guard keeps ALL at 0
  $text .= "#--- " . arp('ALL') . "\n"
    . '{"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "ALL", "cnt-total": "0"}}}' . "\n"
    . "#--- " . nd('ALL') . "\n"
    . '{"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "ALL", "TABLE_afi": {"ROW_afi": {"afi": "ipv6", "count": "0"}}}}}' . "\n";
  my $ssh = fake_ssh(text => $text);
  my $result = by_vrf($ssh);
  is $result->{vrf_read}->{ALL}, 0, 'reported as 0';
  is_deeply [ grep { /\bvrf all\b/i } $ssh->commands ], [], 'no command for it';
  is $result->{vrf_read}->{red}, 1, 'red whole';
};

subtest 'arpnip_by_vrf__chained_reply__entries_under_their_vrf' => sub {
  my $ssh = fake_ssh(text => slurp($CHAIN_FIXTURE));
  my $chained = by_vrf($ssh);
  is_deeply chains_sent($ssh), [ lab_requests() ], 'two chained exec requests';
  my $per_command = by_vrf(fake_ssh());
  is_deeply $chained->{vrf_read}, \%LAB_READ, 'every VRF read whole';
  is_deeply $chained->{entries}, $per_command->{entries}, 'the entries the per-command replies give';
  is scalar(@{ entries_in($chained, 'red') }), 2 + 6, 'red: 2 ARP rows and 6 neighbors';
};

subtest 'arpnip_by_vrf__chained_reply_missing_one_document__only_that_vrf_family_unread' => sub {
  my $text = chain_with(sub { grep { !/"vrf-name-out": "green", "TABLE_afi"/ } @_ });
  my $result = by_vrf(fake_ssh(text => $text));
  is_deeply $result->{vrf_read}, { %LAB_READ, green => 0 }, 'only green unread';
  is_deeply entries_in($result, 'green'), [], 'its other family has no rows either';
  is scalar(@{ entries_in($result, 'red') }), 2 + 6, 'red unaffected';
};

subtest 'arpnip_by_vrf__chained_reply_out_of_order__assigned_by_content' => sub {
  my $result = by_vrf(fake_ssh(text => chain_with(sub { reverse @_ })));
  my $per_command = by_vrf(fake_ssh());
  is_deeply $result->{vrf_read}, \%LAB_READ, 'every VRF read whole';
  is_deeply [ sort map { "$_->{vrf} $_->{ip} $_->{mac}" } @{ $result->{entries} } ],
            [ sort map { "$_->{vrf} $_->{ip} $_->{mac}" } @{ $per_command->{entries} } ],
    'each entry under the VRF its document names';
};

subtest 'arpnip_by_vrf__duplicate_document__that_vrf_family_unread' => sub {
  my $text = chain_with(sub { map { ($_, /"vrf-name-out": "red", "cnt-total"/ ? $_ : ()) } @_ });
  my $result = by_vrf(fake_ssh(text => $text));
  is_deeply $result->{vrf_read}, { %LAB_READ, red => 0 }, 'only red unread';
  is scalar(grep { /^10\./ } @{ entries_in($result, 'red') }), 0, 'neither copy of its ARP table is taken';
};

subtest 'arpnip_by_vrf__undecodable_fragment__rest_of_request_unread' => sub {
  my $text = chain_with(sub {
    my @docs = @_;
    splice @docs, 8, 0, '{"TABLE_vrf": {"ROW_vrf": {"vrf-na';
    return @docs;
  }, 0);
  my $result = by_vrf(fake_ssh(text => $text));
  is_deeply $result->{vrf_read},
    { %LAB_READ, grey => 0, management => 0 },
    'grey and the rest of its request unread, the next request read';
  is scalar(@{ entries_in($result, 'blue') }), 2 + 7, 'documents before it are kept';
};

# VRF names in each chained request sent
sub groups_of { return [ map { [ /show ip arp vrf (\S+) \|/g ] } @{ chains_sent($_[0]) } ] }

# nine VRFs are 18 commands; the 640 byte cap stops a request before the 16
# command cap can (eight 1-character VRFs already take 661 bytes)
subtest 'arpnip_by_vrf__more_than_16_commands__split_into_requests' => sub {
  my ($text, @names) = many_vrf_text();
  my $ssh = fake_ssh(text => $text);
  my $result = by_vrf($ssh);
  my $chains = chains_sent($ssh);
  cmp_ok scalar(@$chains), '>', 1, 'split into several requests';
  is scalar(grep { length $_ > 640 or 16 < scalar(split / ; /) } @$chains), 0, 'each within both caps';
  is_deeply [ map { @$_ } @{ groups_of($ssh) } ], \@names, 'every VRF asked once, in list order';
  is_deeply $result->{vrf_read}, { '' => 1, map { ("v$_" => 1) } 1 .. 8 }, 'all read whole';
};

subtest 'arpnip_by_vrf__capture_error_on_one_request__other_requests_read' => sub {
  my ($text, @names) = many_vrf_text();
  my @groups = @{ groups_of(do { my $ssh = fake_ssh(text => $text); by_vrf($ssh); $ssh }) };
  my %all = map { ($_ eq 'default' ? '' : $_) => 1 } @names;
  my $last = by_vrf(fake_ssh(text => $text, timeout_on => [ arp($groups[-1][0]) ]));
  is_deeply $last->{vrf_read},
    { %all, map { ($_ eq 'default' ? '' : $_) => 0 } @{ $groups[-1] } }, 'only the last request unread';
  my $first = by_vrf(fake_ssh(text => $text, timeout_on => [ arp($groups[0][0]) ]));
  is_deeply $first->{vrf_read},
    { %all, map { ($_ eq 'default' ? '' : $_) => 0 } @{ $groups[0] } }, 'only the first request unread';
  is $first->{vrf_list_complete}, 1, 'the list was whole';
};

subtest 'arpnip_by_vrf__document_for_vrf_not_asked__ignored' => sub {
  my $text = chain_with(sub { (@_, '{"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "stray", "cnt-total": "0"}}}') });
  my $result = by_vrf(fake_ssh(text => $text));
  is_deeply $result->{vrf_read}, \%LAB_READ, 'the others are unaffected';
  ok !exists $result->{vrf_read}->{stray}, 'and stray is not reported';
};

subtest 'arpnip_by_vrf__names_differ_only_in_case__all_unread_list_incomplete' => sub {
  my $text = with_output('show vrf | json',
    '{"TABLE_vrf": {"ROW_vrf": [{"vrf_name": "default"}, {"vrf_name": "Red"}, {"vrf_name": "red"}, {"vrf_name": "blue"}]}}' . "\n");
  my $ssh = fake_ssh(text => $text);
  my $result = by_vrf($ssh);
  is_deeply $result->{vrf_read}, { '' => 1, Red => 0, red => 0, blue => 1 }, 'both spellings unread';
  is scalar(grep { /vrf red/i } $ssh->commands), 0, 'no command for either';
  is_deeply entries_in($result, $_), [], "no entries under $_" for qw/Red red/;
  is $result->{vrf_list_complete}, 0, 'list not vouched';
};

subtest 'arpnip_by_vrf__long_names__requests_capped_at_640_bytes' => sub {
  my @names = ('default', map { sprintf 'long-vrf-name-%02d-', $_ } 1 .. 11);
  @names = map { $_ eq 'default' ? $_ : $_ . ('x' x (40 - length $_)) } @names;
  my ($text) = many_vrf_text(@names);
  my $ssh = fake_ssh(text => $text);
  my $result = by_vrf($ssh);
  my $chains = chains_sent($ssh);
  cmp_ok scalar(@$chains), '>', 1, 'split into several requests';
  is scalar(grep { length $_ > 640 } @$chains), 0, 'none over 640 bytes';
  ok scalar(grep { scalar(split / ; /) < 16 } @$chains), 'split by bytes, not by the 16 command cap';
  is_deeply [ sort keys %{ $result->{vrf_read} } ], [ sort map { $_ eq 'default' ? '' : $_ } @names ], 'every VRF reported';
  is scalar(grep { !$_ } values %{ $result->{vrf_read} }), 0, 'all read whole';
};

subtest 'arpnip_by_vrf__uses_exec_requests_only__no_pty' => sub {
  my $ssh = fake_ssh();
  my (@calls, $pty_opened);
  no warnings qw/redefine once/;
  my $capture = \&Test::Netdisco::FakeSSH::capture;
  local *Test::Netdisco::FakeSSH::capture = sub { push @calls, [ @_[1 .. $#_] ]; goto &$capture };
  local *Test::Netdisco::FakeSSH::open2pty = sub { ++$pty_opened; return };
  by_vrf($ssh);
  ok !$pty_opened, 'no pty opened';
  is scalar(@calls), 3, 'the list and two chained requests went through capture';
  is scalar(grep { ref $_->[0] or @$_ != 1 } @calls), 0, 'each a plain command string, no stdin_data';
};

subtest 'arpnip_by_vrf__unsafe_vrf_name__unread_without_a_command' => sub {
  my $text = with_output('show vrf | json',
    '{"TABLE_vrf": {"ROW_vrf": [{"vrf_name": "red"}, {"vrf_name": "a b | x"}]}}' . "\n");
  my $ssh = fake_ssh(text => $text);
  my $result = by_vrf($ssh);
  is $result->{vrf_read}->{'a b | x'}, 0, 'unread';
  is scalar(grep { /a b/ } $ssh->commands), 0, 'never sent';
  is $result->{vrf_read}->{red}, 1, 'red whole';
};

subtest 'arpnip__lab_text__unchanged' => sub {
  my $ssh = Test::Netdisco::FakeSSH->new(text => slurp($TEXT_FIXTURE));
  my $guard = $ssh->install_expect;
  my @entries = $NXOS->arpnip('switch', $ssh, {});

  is_deeply [$ssh->commands], [
    'show ip arp vrf all | inc ^[1-9] | no-more',
    'show ipv6 neighbor vrf all | exclude Flags: | no-more',
  ], 'the commands arpnip has always sent';
  is_deeply [ map { "$_->{ip} $_->{mac}" } @entries ], [
    '172.20.20.1 92f9.ea9d.aeda', '10.10.10.2 0200.0000.0201', '10.10.10.2 0200.0000.0202',
    '10.11.0.2 0200.0000.0203', '10.12.0.2 0200.0000.0203',
    '2001:db8:10::2 0200.0000.0201', '2001:db8:10::ff:fe00:201 0200.0000.0201',
    'fe80::2 0200.0000.0201',
    '2001:db8:13::2 0200.0000.0204', '2001:db8:13::ff:fe00:204 0200.0000.0204',
  ], 'the entries arpnip has always returned, in the device format';
  is_deeply [ sort keys %{ $entries[0] } ], [qw/ip mac/], 'no vrf key';
};

subtest 'arpnip_by_vrf__through_the_worker__entries_keep_their_vrf' => sub {
  my $ssh = fake_ssh();
  my $cli = bless {}, 'NxosCliStub';
  { no strict 'refs'; *{'NxosCliStub::arpnip_by_vrf'} = sub { by_vrf($ssh) }; }

  delete @{ vars() }{qw/arps vrf_read vrf_read_families vrf_list_complete/};
  vars->{'arps'} = {};
  my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });
  my $status = App::Netdisco::Worker::Plugin::Arpnip::Nodes::gather_arps_by_vrf_cli($device, $cli);
  ok $status->is_ok, 'worker done';

  my @arps = values %{ vars->{'arps'} };
  is scalar(grep { $_->{ip} eq '10.10.10.2' and $_->{vrf} eq 'red' } @arps), 1, '10.10.10.2 in red';
  is scalar(grep { $_->{ip} eq '10.10.10.2' and $_->{vrf} eq 'blue' } @arps), 1, '10.10.10.2 in blue';
  is scalar(grep { $_->{ip} eq '172.20.20.1' and $_->{vrf} eq 'management' } @arps), 1, 'management named';
  is_deeply vars->{'vrf_read'}, { %LAB_READ }, 'vrf_read reaches the worker whole, default as the empty name';
  is vars->{'vrf_list_complete'}, 1, 'list complete';
};

# subnets_by_vrf: the connected-route commands for all VRFs, one exec request
# each. 'direct' lists only connected and local-direct routes; the worker drops
# host routes, so the capture's /32 and /128 are returned here.
my $ROUTES_FIXTURE = 'xt/data/sshcollector/nxos/nxos9300v-routes.txt';
my $V4_ROUTES = 'show ip route direct vrf all | json';
my $V6_ROUTES = 'show ipv6 route direct vrf all | json';

sub routes_ssh {
  my ($text, @timeout_on) = @_;
  my $ssh = Test::Netdisco::FakeSSH->new(text => $text // slurp($ROUTES_FIXTURE));
  $ssh->timeout_on($_) for @timeout_on;
  return $ssh;
}

sub routes_text_with {
  my ($command, $output) = @_;
  (my $text = slurp($ROUTES_FIXTURE)) =~ s/^(#--- \Q$command\E\n).*?(?=^#---|\z)/$1$output/ms
    or die "no section $command";
  return $text;
}

sub capture_nxos_info {
  my $code = shift;
  my @logged;
  no warnings 'redefine';
  local *App::Netdisco::SSHCollector::Platform::NXOS::info = sub { push @logged, join '', @_ };
  my $result = $code->();
  return ($result, @logged);
}

sub prefixes_by_vrf {
  my ($result) = @_;
  return { map { my $vrf = $_; ($vrf => [ sort map { "$_->{prefix}/$_->{len}" } @{ $result->{$vrf} } ]) } keys %$result };
}

my @LAB_V4 = (
  management => ['172.20.20.0/24'],
  red => ['10.10.10.0/24', '10.11.0.0/24'],
  blue => ['10.10.10.0/24', '10.12.0.0/24'],
  grey => ['10.14.0.1/32'],
);

sub lab_prefixes {
  my %by_vrf = @LAB_V4;
  return \%by_vrf;
}

subtest 'nxos_subnets_by_vrf__lab_capture__prefixes_keyed_by_vrf' => sub {
  my $ssh = routes_ssh();
  my $result = $NXOS->subnets_by_vrf('switch', $ssh, {});

  is_deeply [$ssh->commands], [$V4_ROUTES, $V6_ROUTES], 'the two direct route commands, one exec request each';
  my $got = prefixes_by_vrf($result);
  ok !exists $got->{default}, 'default has no connected routes, so it is absent';
  ok exists $got->{management}, 'management present';
  is_deeply $got->{management}, ['172.20.20.0/24'], 'management IPv4';
  is_deeply $got->{red}, [ sort '10.10.10.0/24', '10.11.0.0/24', '2001:db8:10::/64', '2001:db8:11::/64' ],
    'red: IPv4 and IPv6 together';
  is_deeply $got->{green}, ['2001:db8:13::/64'], 'green: IPv6 only, its empty IPv4 table adds nothing';
  is_deeply $got->{grey}, [ sort '10.14.0.1/32', '2001:db8:14::1/128' ],
    'host routes are returned as the device lists them: the worker filters';
  is_deeply [ sort keys %$result ], [qw/blue green grey management red/], 'every VRF with a connected route';
  is_deeply [ sort keys %{ $result->{red}->[0] } ], [qw/len prefix/], 'entry keys';
};

subtest 'nxos_subnets_by_vrf__same_prefix_in_two_vrfs__one_row_per_vrf' => sub {
  my $result = $NXOS->subnets_by_vrf('switch', routes_ssh(), {});
  is scalar(grep { $_->{prefix} eq '10.10.10.0' and $_->{len} == 24 } @{ $result->{red} }), 1, 'in red';
  is scalar(grep { $_->{prefix} eq '10.10.10.0' and $_->{len} == 24 } @{ $result->{blue} }), 1, 'in blue';
  is scalar(grep { $_->{prefix} eq '2001:db8:10::' and $_->{len} == 64 } @{ $result->{red} }, @{ $result->{blue} }), 2,
    'the shared IPv6 prefix once per VRF';
  is_deeply [ grep { /^10\.10\.10\.0\/24$/ } @{ prefixes_by_vrf($result)->{red} } ], ['10.10.10.0/24'], 'not doubled';
};

subtest 'nxos_subnets_by_vrf__single_row__hash_not_array_parsed' => sub {
  my $got = prefixes_by_vrf($NXOS->subnets_by_vrf('switch', routes_ssh(), {}));
  is_deeply $got->{management}, ['172.20.20.0/24'], 'a ROW_prefix hash is one prefix';

  my $one_vrf = '{"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "solo", "TABLE_addrf": {"ROW_addrf": '
    . '{"addrf": "ipv4", "TABLE_prefix": {"ROW_prefix": {"ipprefix": "192.0.2.0/25"}}}}}}}';
  my $text = routes_text_with($V4_ROUTES, "$one_vrf\n");
  $text =~ s/^(#--- \Q$V6_ROUTES\E\n).*?(?=^#---|\z)/$1\{"TABLE_vrf": \{\}\}\n/ms or die;
  is_deeply prefixes_by_vrf($NXOS->subnets_by_vrf('switch', routes_ssh($text), {})), { solo => ['192.0.2.0/25'] },
    'ROW_vrf, ROW_addrf and ROW_prefix all hashes';

  my $two_addrf = '{"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "dual", "TABLE_addrf": {"ROW_addrf": ['
    . '{"addrf": "ipv4", "TABLE_prefix": {"ROW_prefix": [{"ipprefix": "192.0.2.0/25"}, {"ipprefix": "198.51.100.0/24"}]}},'
    . '{"addrf": "ipv4"}]}}}}';
  $text = routes_text_with($V4_ROUTES, "$two_addrf\n");
  is_deeply prefixes_by_vrf($NXOS->subnets_by_vrf('switch', routes_ssh($text), {}))->{dual},
    ['192.0.2.0/25', '198.51.100.0/24'], 'ROW_addrf and ROW_prefix as arrays';
};

subtest 'nxos_subnets_by_vrf__egress_loadbalance_name__passed_through' => sub {
  my $one = '{"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "egress-loadbalance-resolution-", '
    . '"TABLE_addrf": {"ROW_addrf": {"addrf": "ipv4", "TABLE_prefix": {"ROW_prefix": {"ipprefix": "192.0.2.0/25"}}}}}}}';
  my $result = $NXOS->subnets_by_vrf('switch', routes_ssh(routes_text_with($V4_ROUTES, "$one\n")), {});
  ok exists $result->{'egress-loadbalance-resolution-'}, 'the name is the device\'s own';
};

subtest 'nxos_subnets_by_vrf__ipv6_fails__ipv4_still_returned' => sub {
  my $expected = lab_prefixes();

  my ($result, @logged) = capture_nxos_info(sub {
    $NXOS->subnets_by_vrf('switch', routes_ssh(routes_text_with($V6_ROUTES, qq({"TABLE_vrf": \n))), {}) });
  is_deeply prefixes_by_vrf($result), $expected, 'undecodable IPv6 reply, IPv4 returned';
  is scalar(@logged), 1, 'logged once';
  like $logged[0] // '', qr/IPv6 route/, 'names the failed command';

  ($result, @logged) = capture_nxos_info(sub { $NXOS->subnets_by_vrf('switch', routes_ssh(undef, $V6_ROUTES), {}) });
  is_deeply prefixes_by_vrf($result), $expected, 'capture error on IPv6 (inactivity timeout), IPv4 returned';
  is scalar(@logged), 1, 'logged once';

  $result = $NXOS->subnets_by_vrf('switch', routes_ssh(undef, $V4_ROUTES), {});
  is_deeply [ sort keys %$result ], [qw/blue green grey red/], 'capture error on IPv4, IPv6 returned';
  is_deeply prefixes_by_vrf($result)->{green}, ['2001:db8:13::/64'], 'IPv6 prefixes present';
};

subtest 'nxos_subnets_by_vrf__error_reply__family_contributes_nothing' => sub {
  my $error = "Syntax error while parsing 'show ip route direkt vrf all | json'\n\n\nCmd exec error.\n";
  my $result = $NXOS->subnets_by_vrf('switch', routes_ssh(routes_text_with($V4_ROUTES, $error)), {});
  is_deeply [ sort keys %$result ], [qw/blue green grey red/], 'the Syntax error reply is skipped, IPv6 stands';
  is_deeply prefixes_by_vrf($result)->{red}, ['2001:db8:10::/64', '2001:db8:11::/64'], 'only IPv6 under red';

  my $both = routes_text_with($V6_ROUTES, $error);
  $both =~ s/^(#--- \Q$V4_ROUTES\E\n).*?(?=^#---|\z)/$1$error/ms or die;
  is $NXOS->subnets_by_vrf('switch', routes_ssh($both), {}), undef, 'both error replies: undef';
};

subtest 'nxos_subnets_by_vrf__wrong_shape__family_contributes_nothing' => sub {
  foreach my $reply ('[]', '"none"', '{"TABLE_vrf": []}', '{"TABLE_vrf": {"ROW_vrf": "x"}}', '{"other": {}}', 'null') {
    my $text = routes_text_with($V6_ROUTES, "$reply\n");
    my $result = eval { $NXOS->subnets_by_vrf('switch', routes_ssh($text), {}) };
    is $@, '', "$reply does not die";
    is_deeply prefixes_by_vrf($result)->{red}, ['10.10.10.0/24', '10.11.0.0/24'], "IPv4 stands ($reply)";
  }
};

subtest 'nxos_subnets_by_vrf__both_fail__returns_undef' => sub {
  my ($result, @logged) = capture_nxos_info(sub { [ $NXOS->subnets_by_vrf('switch', routes_ssh(undef, $V4_ROUTES, $V6_ROUTES), {}) ] });
  is_deeply $result, [undef], 'both capture errors: undef';
  is scalar(@logged), 2, 'one info line per failed command';

  my $text = routes_text_with($V4_ROUTES, "garbage\n");
  $text =~ s/^(#--- \Q$V6_ROUTES\E\n).*?(?=^#---|\z)/$1garbage\n/ms or die;
  is $NXOS->subnets_by_vrf('switch', routes_ssh($text), {}), undef, 'both undecodable: undef';
};

subtest 'nxos_subnets_by_vrf__unnamable_vrf_row__contributes_nothing_others_stand' => sub {
  foreach my $name ('{"x": 1}', '""', '["red"]', 'null') {
    my $rows = qq({"vrf-name-out": $name, "TABLE_addrf": {"ROW_addrf": {"addrf": "ipv4", )
      . q("TABLE_prefix": {"ROW_prefix": {"ipprefix": "192.0.2.0/25"}}}}});
    my $reply = qq({"TABLE_vrf": {"ROW_vrf": [$rows, {"vrf-name-out": "solo", "TABLE_addrf": )
      . q({"ROW_addrf": {"addrf": "ipv4", "TABLE_prefix": {"ROW_prefix": {"ipprefix": "198.51.100.0/24"}}}}}]}});
    my $result = $NXOS->subnets_by_vrf('switch', routes_ssh(routes_text_with($V4_ROUTES, "$reply\n")), {});
    is_deeply [ grep { /^(?:HASH|ARRAY)|^$/ } keys %$result ], [], "no junk or global key for name $name";
    is_deeply prefixes_by_vrf($result)->{solo}, ['198.51.100.0/24'], "the named row stands ($name)";
    ok !grep({ $_->{prefix} eq '192.0.2.0' } map { @$_ } values %$result), "the unnamable row stored nowhere ($name)";
  }
};

subtest 'nxos_subnets_by_vrf__inner_shapes_wrong__row_contributes_nothing_not_dying' => sub {
  my $good = '{"ipprefix": "192.0.2.0/25"}';
  my $addrf = sub { qq({"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "solo", "TABLE_addrf": $_[0]}}}) };
  my %replies = (
    'ROW_addrf is a string' => $addrf->('{"ROW_addrf": "x"}'),
    'TABLE_addrf is a list' => $addrf->('[]'),
    'ROW_prefix element is a string' => $addrf->(qq({"ROW_addrf": {"TABLE_prefix": {"ROW_prefix": ["x", 7]}}})),
    'ipprefix is an object' => $addrf->(q({"ROW_addrf": {"TABLE_prefix": {"ROW_prefix": {"ipprefix": {"a": 1}}}}})),
  );
  foreach my $label (sort keys %replies) {
    my $text = routes_text_with($V4_ROUTES, "$replies{$label}\n");
    my $result = eval { $NXOS->subnets_by_vrf('switch', routes_ssh($text), {}) };
    is $@, '', "$label does not die";
    ok !exists $result->{solo}, "$label: nothing stored";
    is_deeply prefixes_by_vrf($result)->{red}, ['2001:db8:10::/64', '2001:db8:11::/64'], "$label: IPv6 stands";
  }
};

subtest 'nxos_subnets_by_vrf__prefix_without_length__passed_through_for_the_worker_to_drop' => sub {
  my $reply = '{"TABLE_vrf": {"ROW_vrf": {"vrf-name-out": "solo", "TABLE_addrf": {"ROW_addrf": '
    . '{"TABLE_prefix": {"ROW_prefix": {"ipprefix": "192.0.2.0"}}}}}}}';
  my $result = $NXOS->subnets_by_vrf('switch', routes_ssh(routes_text_with($V4_ROUTES, "$reply\n")), {});
  is_deeply $result->{solo}, [ { prefix => '192.0.2.0', len => undef } ],
    'returned with an undef length; vrf_subnet_cidr drops it (xt/204 tests the worker side)';
};

subtest 'nxos_subnets_by_vrf__exec_requests__no_pty' => sub {
  my $ssh = routes_ssh();
  my ($pty_opened, @calls);
  no warnings qw/redefine once/;
  my $capture = \&Test::Netdisco::FakeSSH::capture;
  local *Test::Netdisco::FakeSSH::capture = sub { push @calls, [ @_[1 .. $#_] ]; goto &$capture };
  local *Test::Netdisco::FakeSSH::open2pty = sub { ++$pty_opened; return };
  $NXOS->subnets_by_vrf('switch', $ssh, {});
  ok !$pty_opened, 'no pty opened';
  is_deeply \@calls, [ [$V4_ROUTES], [$V6_ROUTES] ], 'each a plain command string, as arpnip_by_vrf sends them';
};

subtest 'nxos_subnets__unchanged' => sub {
  my $command = 'show ip route vrf all | inc attached | exc /32 | no-more ';
  my $text = "#prompt: switch# \n#--- $command\n"
    . "10.1.1.0/24, ubest/mbest: 1/0, attached\n10.2.0.0/16, ubest/mbest: 1/0, attached\n";
  my $ssh = Test::Netdisco::FakeSSH->new(text => $text);
  my $guard = $ssh->install_expect;
  my @rows = $NXOS->subnets('switch', $ssh, {});
  is_deeply [$ssh->commands], [$command], 'the one pty command subnets has always sent';
  is_deeply \@rows, ['10.1.1.0/24', '10.2.0.0/16'], 'the flat IPv4 list';
};

done_testing;
