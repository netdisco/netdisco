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

# NX-OS arpnip_by_vrf against a 9300v lab capture: one exec request per VRF
# and address family, each judged whole on its own count, so a bad name or an
# undecodable reply spoils only the reads it touches.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

my $FIXTURE = 'xt/data/sshcollector/nxos/nxos9300v.txt';
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

sub arp { return "show ip arp vrf $_[0] | json | no-more" }
sub nd  { return "show ipv6 neighbor vrf $_[0] | json | no-more" }

my %LAB_READ = ('' => 1, blue => 1, 'egress-loadbalance-resolution-' => 1,
                green => 1, grey => 1, management => 1, red => 1);
my @LISTED = qw/blue default egress-loadbalance-resolution- green grey management red/;

subtest 'arpnip_by_vrf__lab_capture__entries_under_their_vrf' => sub {
  my $ssh = fake_ssh();
  my $result = by_vrf($ssh);

  is_deeply [$ssh->commands], [
    'show vrf | json',
    (map { (arp($_), nd($_)) } @LISTED),
  ], 'commands in order';

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
  is $result->{vrf_read}->{blue}, 0, 'blue unread when the reply names red';
  is scalar(grep { /^10\./ } @{ entries_in($result, 'blue') }), 0, 'its ARP rows are not taken';
  is $result->{vrf_read}->{red}, 1, 'red whole';

  (my $cased = slurp($FIXTURE)) =~ s/"vrf-name-out": "green"/"vrf-name-out": "GREEN"/g;
  my $same = by_vrf(fake_ssh(text => $cased));
  is $same->{vrf_read}->{green}, 1, 'case differences are the same VRF';
  ok !exists $same->{vrf_read}->{GREEN}, 'the listed name is used';
};

subtest 'arpnip_by_vrf__capture_error_on_one_vrf__that_vrf_unread' => sub {
  my $result = by_vrf(fake_ssh(timeout_on => [ arp('blue') ]));
  is $result->{vrf_read}->{blue}, 0, 'blue unread';
  is $result->{vrf_read}->{red}, 1, 'other VRFs still read';
  is $result->{vrf_list_complete}, 1, 'the list was whole';
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
  ok scalar(grep { $_ eq arp('default') } $ssh->commands), 'show ip arp vrf default was sent';
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

subtest 'arpnip_by_vrf__uses_exec_requests_only__no_pty' => sub {
  my $ssh = fake_ssh();
  my (@calls, $pty_opened);
  no warnings qw/redefine once/;
  my $capture = \&Test::Netdisco::FakeSSH::capture;
  local *Test::Netdisco::FakeSSH::capture = sub { push @calls, [ @_[1 .. $#_] ]; goto &$capture };
  local *Test::Netdisco::FakeSSH::open2pty = sub { ++$pty_opened; return };
  by_vrf($ssh);
  ok !$pty_opened, 'no pty opened';
  is scalar(@calls), 1 + 2 * @LISTED, 'every command went through capture';
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

done_testing;
