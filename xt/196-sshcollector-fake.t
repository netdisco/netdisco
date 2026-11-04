use strict;
use warnings;

use Test::More;
use Test::Exception;
use lib 'xt/lib';
use Test::Netdisco::FakeSSH;

# Fixture bytes matter: the blank line and the leading spaces must come back untouched.
my $fixture = join '', map { "$_\n" }
    '#prompt: sw1#',
    '#--- terminal length 0',
    '#--- show ip arp',
    'Protocol  Address',
    '',
    '  Internet  10.0.0.1',
    '#--- show vrf',
    'Name  Default RD';

sub fresh { return Test::Netdisco::FakeSSH->new(text => $fixture) }

subtest 'capture__known_command__returns_lines_and_records_it' => sub {
    my $ssh = fresh();
    my @lines = $ssh->capture({ stdin_data => "show ip arp\n" });
    is_deeply \@lines, ["Protocol  Address\n", "\n", "  Internet  10.0.0.1\n"];
    is $ssh->error, '', 'no error';
    is_deeply [$ssh->commands], ['show ip arp'];
    is scalar($ssh->capture('show vrf')), "Name  Default RD\n", 'plain argument, scalar context';
};

subtest 'capture__timeout_injected__sets_error_and_returns_nothing' => sub {
    my $ssh = fresh()->timeout_on('show ip arp');
    my @lines = $ssh->capture('show ip arp');
    is scalar(@lines), 0, 'no lines';
    like $ssh->error, qr/timed out/, 'error set';
};

subtest 'open2pty__send_and_expect__returns_text_before_next_prompt' => sub {
    my $ssh   = fresh();
    my $guard = $ssh->install_expect;
    my ($pty, $pid) = $ssh->open2pty;
    ok $pty && $pid, 'pty and pid';
    my $exp = Expect->init($pty);
    $exp->raw_pty(1);

    my ($pos, $err, $match, $before) = $exp->expect(5, -re => qr/sw1#/);
    is $pos, 1, 'initial prompt seen';
    is $match, 'sw1#';

    $exp->send("show ip arp\n");
    ($pos, $err, $match, $before) = $exp->expect(5, -re => qr/sw1#/);
    is $before, "Protocol  Address\n\n  Internet  10.0.0.1\n", 'blank line and indent exact';
    is $exp->before, $before, 'before accessor agrees';
    is $match, 'sw1#';
};

subtest 'expect__timeout_injected__returns_undef_pos_with_partial_output' => sub {
    my $ssh   = fresh()->timeout_on('show vrf');
    my $guard = $ssh->install_expect;
    my $exp   = Expect->init(($ssh->open2pty)[0]);
    $exp->expect(5, -re => qr/#/);
    $exp->send("show vrf\n");
    my ($pos, $err, $match, $before) = $exp->expect(5, -re => qr/#/);
    ok !defined $pos, 'pos undef';
    is $err, '1:TIMEOUT';
    is $before, "Name  Default RD\n", 'partial output kept';
};

subtest 'commands__pty_session__lists_commands_in_order' => sub {
    my $ssh   = fresh();
    my $guard = $ssh->install_expect;
    my $exp   = Expect->init(($ssh->open2pty)[0]);
    $exp->expect(5, -re => qr/#/);
    $exp->send("terminal length 0\n");
    $exp->expect(5, -re => qr/#/);
    $exp->send("show vrf\n");
    is_deeply [$ssh->commands], ['terminal length 0', 'show vrf'];
};

subtest 'send__unknown_command__dies_listing_known_commands' => sub {
    my $ssh   = fresh();
    my $guard = $ssh->install_expect;
    my $exp   = Expect->init(($ssh->open2pty)[0]);
    throws_ok { $exp->send("show nonsense\n") } qr/no fixture section for command 'show nonsense'.*'show vrf'/;
};

subtest 'install_expect__guard_released__restores_real_init' => sub {
    my $original = \&Expect::init;
    { my $guard = fresh()->install_expect; isnt \&Expect::init, $original, 'replaced'; }
    is \&Expect::init, $original, 'restored';
};

subtest 'IOSXE_arpnip__driven_unmodified__runs_against_the_fake' => sub {
    require App::Netdisco::SSHCollector::Platform::IOSXE;
    my $ssh = Test::Netdisco::FakeSSH->new(text => join '', map { "$_\n" }
        '#prompt: sw1#',
        '#--- terminal length 0',
        '#--- show ip arp',
        'Protocol  Address  Age  Hardware Addr  Type  Interface',
        'Internet  10.0.0.1  5  aabb.ccdd.eeff  ARPA  Vlan1',
        '#--- show vrf',
        'Name  Default RD  Protocols  Interfaces',
        '#--- exit');
    my $guard = $ssh->install_expect;
    my @rows = App::Netdisco::SSHCollector::Platform::IOSXE->arpnip('sw1', $ssh, {});
    is scalar(@rows), 1, 'one entry';
    is $rows[0]{ip}, '10.0.0.1', 'ip parsed';
    is $rows[0]{mac}, 'aa:bb:cc:dd:ee:ff', 'mac parsed';
    is_deeply [$ssh->commands], ['terminal length 0', 'show ip arp', 'show vrf', 'exit'];
};

subtest 'fake_expect__timeout_then_next_command__partial_output_carries_over' => sub {
    my $ssh   = fresh()->timeout_on('show vrf');
    my $guard = $ssh->install_expect;
    my $exp   = Expect->init(($ssh->open2pty)[0]);
    $exp->expect(5, -re => qr/sw1#/);
    $exp->send("show vrf\n");
    $exp->expect(5, -re => qr/sw1#/);
    $exp->send("show ip arp\n");
    my ($pos, $err, $match, $before) = $exp->expect(5, -re => qr/sw1#/);
    is $before, "Name  Default RD\nProtocol  Address\n\n  Internet  10.0.0.1\n",
        'stale partial output is prepended, as real Expect keeps its accumulator';
};

subtest 'capture__failure_then_success__error_does_not_stick' => sub {
    my $ssh = fresh()->timeout_on('show ip arp');
    $ssh->capture('show ip arp');
    ok $ssh->error, 'first capture failed';
    my @lines = $ssh->capture('show vrf');
    is $ssh->error, '', 'error cleared by the next capture';
    is scalar(@lines), 1, 'second capture returned its lines';
};

subtest 'capture__options_without_stdin_data__dies_with_guidance' => sub {
    throws_ok { fresh()->capture({}) } qr/needs a command argument/;
};

subtest 'install_expect__real_handle__falls_through_to_real_init' => sub {
    my $guard = fresh()->install_expect;
    pipe(my $reader, my $writer) or die "pipe: $!";
    my $exp = Expect->init($reader);
    isa_ok $exp, 'Expect', 'not the fake';
    isnt ref $exp, 'Test::Netdisco::FakeSSH::Expect';
};

subtest 'capture__chained_commands__exact_section_wins_else_parts_joined' => sub {
    my $text = join '', map { "$_\n" }
        '#--- one', '1', '#--- two', '2', '#--- one ; two', 'chain section';
    is scalar(Test::Netdisco::FakeSSH->new(text => $text)->capture('one ; two')),
        "chain section\n", 'an exact section for the chain wins';

    my $parts = join '', map { "$_\n" } '#--- one', '1', '#--- two', '2';
    my $ssh = Test::Netdisco::FakeSSH->new(text => $parts);
    is scalar($ssh->capture('one ; two')), "1\n2\n", 'no section of its own: parts joined, one line each';
    is_deeply [$ssh->commands], ['one ; two'], 'recorded as the one chained command';

    $ssh->timeout_on('two');
    is scalar($ssh->capture('one ; two')), '', 'a timeout on any part times out the chain';
    like $ssh->error, qr/timed out/, 'with an error';
    is scalar($ssh->capture('one')), "1\n", 'the part alone still answers';
};

done_testing;
