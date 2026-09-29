#!/usr/bin/env perl

# A munger reaches decode_and_munge from the request and names both a class to
# load and a sub to call, so only SNMP::Info's own namespace is accepted.
#
# Two things shape the cases below. Legitimate mungers are not all named
# munge_*, so the allowlist is by namespace rather than by prefix, and a
# refused munger must return the value unmunged rather than raise, so a stale
# choice in the browser cannot break the page. Test::Netdisco::MungerProbe
# exists so a refusal can be proven by absence from %INC, not merely by output.

use strict;
use warnings;

use Test::More 0.88;
use Module::Load ();
use MIME::Base64 'encode_base64';
use JSON::PP ();
use lib 'xt/lib';
use App::Netdisco::Util::SNMP 'decode_and_munge';

my $PROBE = 'Test::Netdisco::MungerProbe';
my $raw   = pack('H*', '001122334455');
my $enc   = JSON::PP->new->encode([ encode_base64($raw, '') ]);

# the encoder is in pretty mode, so every result carries a trailing newline
sub munged { my $out = decode_and_munge($_[0], $enc); chomp $out if defined $out; $out }

my $plain = munged(undef);

subtest 'decodeAndMunge__a_munger_under_SNMP_Info__munges_the_value' => sub {
    is munged('SNMP::Info::munge_mac'), '"00:11:22:33:44:55"',
      'the mac munger is applied';
};

subtest 'decodeAndMunge__a_munger_not_named_munge__still_munges' => sub {
    is munged('SNMP::Info::CiscoStpExtensions::oct2str'),
      '"001122334455"', 'a munger without the munge_ prefix is applied';
};

subtest 'decodeAndMunge__a_class_outside_SNMP_Info__returns_the_value_unmunged' => sub {
    is munged("${PROBE}::probe"), $plain,
      'the value comes back as though no munger was given';
    is munged('App::Netdisco::Util::SNMP::sortable_oid'), $plain,
      "netdisco's own namespace is refused too";
};

subtest 'decodeAndMunge__a_class_outside_SNMP_Info__is_never_loaded' => sub {
    my $path = $PROBE; $path =~ s{::}{/}g; $path .= '.pm';
    ok !exists $INC{$path}, 'not loaded before';
    munged("${PROBE}::probe");
    ok !exists $INC{$path}, 'still not loaded after a refused munger';

    Module::Load::load($PROBE);
    ok exists $INC{$path}, 'the probe is loadable, so absence above is the refusal';
};

subtest 'decodeAndMunge__a_class_only_beginning_like_SNMP_Info__is_refused' => sub {
    is munged('SNMP::InfoEvil::munge_mac'), $plain,
      'the namespace is anchored, not a prefix match';
};

subtest 'decodeAndMunge__no_munger__returns_the_decoded_value' => sub {
    ok defined $plain && length $plain, 'a value with no munger still decodes';
};

done_testing;
