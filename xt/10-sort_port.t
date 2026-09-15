#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };
use JSON::PP 'decode_json';

BEGIN {
    use_ok( 'App::Netdisco::Util::Web', 'sort_port' );
}

#  1 = first is greater
#  0 = same
# -1 = first is lesser

is(sort_port(1,1), 0, 'number - same values');
is(sort_port('1:2','1:10'), -1, 'colon number (Extreme) - first lesser');
is(sort_port('D1','D10'), -1, 'HP - simple letter and number [#152]');

# Juniper examples for [#128]
# https://www.juniper.net/documentation/en_US/junos14.2/topics/concept/interfaces-interface-naming-overview.html
is(sort_port('so-1/0/0.0','so-1/0/1.0'), -1, 'juniper - FPC in slot 1 with OC3 PIC - 1');
is(sort_port('so-1/1/0.0','so-1/1/1.0'), -1, 'juniper - FPC in slot 1 with OC3 PIC - 2');
is(sort_port('so-1/0/0.0','so-1/1/0.0'), -1, 'juniper - FPC in slot 1 with OC3 PIC - 3');

is(sort_port('so-1/0/0:0','so-1/0/1:0'), -1, 'juniper - FPC in slot 1 with OC3 PIC channelized - 1');
is(sort_port('so-1/1/0:0','so-1/1/1:0'), -1, 'juniper - FPC in slot 1 with OC3 PIC channelized - 2');
is(sort_port('so-1/0/0:0','so-1/1/0:0'), -1, 'juniper - FPC in slot 1 with OC3 PIC channelized - 3');

# Order properties over the shared corpus, xt/portsort-corpus.json. The nine
# assertions above say sort_port agrees with a handful of hand picked pairs;
# these say whether it defines an order at all, which is what has to be true
# before that order can move into Postgres.
#
# The corpus is read rather than built here so the JavaScript comparator in
# xt/js/portsort.test.js and this one are measured against the same values. The
# recorded `order` is deliberately NOT asserted for sort_port: with no total
# order there is no sequence it can be held to.

my $corpus = decode_json(do {
    open my $fh, '<:raw', 'xt/portsort-corpus.json'
        or die "xt/portsort-corpus.json: $!";
    local $/; <$fh>;
});
my @names = @{ $corpus->{names} };

# Warnings are trapped rather than disabled, because `no warnings` here is
# lexical to this file and the warnings are emitted inside Web.pm. sort_port
# compares dotted quads such as 10.0.0.1 with <=>, which warns once per
# comparison and would bury this file's output under millions of lines. They are
# a symptom of the same looseness the tests below measure, not a separate defect
# to fix here.
{
    local $SIG{__WARN__} = sub {};

    my @asymmetric;
    foreach my $a (@names) {
        foreach my $b (@names) {
            next if $a eq $b;
            my ($ab, $ba) = (sort_port($a, $b), sort_port($b, $a));
            push @asymmetric, "$a vs $b" if ($ab > 0 and $ba > 0) or ($ab < 0 and $ba < 0);
        }
    }
    is(scalar @asymmetric, 0, 'no pair is greater than itself reversed')
        or diag("asymmetric pairs: @{[ splice @asymmetric, 0, 6 ]}");

    # Both TODO because sort_port genuinely fails them and is not going to be
    # made to pass: the web path is moving to the SQL sort key, and its four
    # remaining callers order log output where the instability is harmless.
    # Recorded here rather than left latent, so the defect is visible to anyone
    # who reaches for this function for something that needs a real order.
    TODO: {
        local $TODO = 'sort_port defines no total order; the Ports tab order comes from portsort.js';

        # Stops at the first violation. There are hundreds, so this is fast
        # while it fails; were it ever fixed the scan becomes O(n^3) and the
        # test should be promoted out of TODO rather than left to run.
        my $intransitive;
        OUTER: foreach my $a (@names) {
            foreach my $b (@names) {
                next unless sort_port($a, $b) < 0;
                foreach my $c (@names) {
                    next unless sort_port($b, $c) < 0;
                    if (sort_port($a, $c) >= 0) {
                        $intransitive = "$a < $b < $c, yet $a is not less than $c";
                        last OUTER;
                    }
                }
            }
        }
        is($intransitive, undef, 'a < b and b < c implies a < c');

        my %sequences;
        my $seed = 12345;
        foreach my $round (1 .. 50) {
            my @shuffled = @names;
            for (my $i = $#shuffled; $i > 0; $i--) {
                $seed = ($seed * 1103515245 + 12345) % 2147483648;
                my $j = int(($seed / 2147483648) * ($i + 1));
                @shuffled[$i, $j] = @shuffled[$j, $i];
            }
            $sequences{ join "\0", sort { sort_port($a, $b) } @shuffled } = 1;
        }
        is(scalar keys %sequences, 1, 'the sorted sequence does not depend on the input order');
    }
}

done_testing;
