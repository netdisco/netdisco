#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 1.302083;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };
use Encode ();

BEGIN {
  use_ok( 'App::Netdisco::Configuration' );
  use_ok( 'App::Netdisco::Util::SNMPText', ':all' );
}

no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

my %words = (
  nihao  => "\x{4f60}\x{597d}",
  cafe   => "caf\x{e9}",
  muller => "M\x{fc}ller",
);

sub sent_as {
  my ($word, $encoding) = @_;
  return Encode::encode($encoding, $words{$word}, Encode::FB_CROAK | Encode::LEAVE_SRC);
}

# expected results, measured 2026-10-17
my %expect = (   # [word, sent_as, fallbacks] => [result_is_word, how]
  'nihao UTF-8 []'      => [1, 'UTF-8'],   'nihao UTF-8 gbk'      => [1, 'UTF-8'],
  'nihao gbk []'        => [0, 'latin1'],  'nihao gbk gbk'        => [1, 'gbk'],
  'cafe UTF-8 []'       => [1, 'UTF-8'],   'cafe iso-8859-1 []'   => [1, 'latin1'],
  'cafe iso-8859-1 gbk' => [1, 'latin1'],  'cafe gbk []'          => [0, 'latin1'],
  'cafe gbk gbk'        => [1, 'gbk'],     'muller UTF-8 gbk'     => [1, 'UTF-8'],
  'muller iso-8859-1 []'=> [1, 'latin1'],
  'muller iso-8859-1 gbk' => [0, 'gbk'],   # documented limitation: fc6c is valid GBK
  'muller gbk gbk'      => [1, 'gbk'],
);

subtest 'decodeSnmpText__matrix__matches_spec' => sub {
  foreach my $key (sort keys %expect) {
    my ($word, $encoding, $fallback) = split ' ', $key;
    my $bytes = sent_as($word, $encoding);
    my $charsets = ($fallback eq '[]') ? [] : [$fallback];
    my ($text, $how) = decode_text_with($bytes, $charsets);
    my ($is_word, $want_how) = @{ $expect{$key} };
    is($text eq $words{$word} ? 1 : 0, $is_word, "$key: result");
    is($how, $want_how, "$key: how");
  }
};

is(scalar decode_text_with("\xc4\xe3\xba\xc3", ['gbk']), "\x{4f60}\x{597d}",
  'decodeSnmpText__reporter_gbk_bytes__decode_with_gbk');

subtest 'decodeSnmpText__ascii__returned_as_is_with_how_ascii' => sub {
  my ($text, $how) = decode_text_with('plain text', ['gbk']);
  is($text, 'plain text');
  is($how, 'ascii');
};

subtest 'decodeSnmpText__empty_and_undef__returned_unchanged' => sub {
  is(scalar decode_text_with('', ['gbk']), '');
  ok(!defined scalar decode_text_with(undef, ['gbk']));
  is(scalar decode_snmp_text('', undef, 'name'), '');
  ok(!defined decode_snmp_text(undef, undef, 'name'));
};

subtest 'decodeSnmpText__failed_decode__leaves_input_bytes_intact' => sub {
  my $latin1_cafe = "caf\xe9";
  decode_text_with($latin1_cafe, ['gbk']);
  is($latin1_cafe, "caf\xe9");
};

subtest 'decodeSnmpText__truncated_gbk__rejected_by_round_trip' => sub {
  my (undef, $how) = decode_text_with("\xc4\xe3\xba", ['gbk']);
  is($how, 'latin1');
};

subtest 'decodeSnmpText__lone_ff__rejected_by_round_trip' => sub {
  my (undef, $how) = decode_text_with("a\xffb", ['gbk']);
  is($how, 'latin1');
};

subtest 'decodeSnmpText__unknown_charset__warns_once_and_is_skipped' => sub {
  my @warnings;
  local *App::Netdisco::Util::SNMPText::warning = sub { push @warnings, @_ };
  my @hows = map { (decode_text_with("caf\xe9", ['no-such-charset']))[1] } 1, 2;
  like($_, qr/^(?:UTF-8|latin1)$/) for @hows;
  is(scalar @warnings, 1, 'exactly one warning');
};

subtest 'decodeSnmpText__already_decoded_string__returned_unchanged' => sub {
  my $decoded = "caf\x{e9} \x{4f60}";
  ok(utf8::is_utf8($decoded));
  is(scalar decode_text_with($decoded, ['gbk']), $decoded);
};

subtest 'decodeSnmpText__latin1_fallback__logs_debug_with_hex' => sub {
  my @messages;
  local *App::Netdisco::Util::SNMPText::debug = sub { push @messages, @_ };
  is(decode_snmp_text("caf\xe9", undef, 'name'), "caf\x{e9}");
  is(scalar @messages, 1);
  like($messages[0], qr/\[-\] name bytes 636166e9 are not UTF-8/);
};

done_testing;
