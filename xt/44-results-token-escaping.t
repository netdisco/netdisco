#!/usr/bin/env perl

use strict;
use warnings;

# The report and search templates embed their result set as a JavaScript
# literal inside a <script> element, and escape_for_script_context() makes that
# safe. Applying it is a one-line before_template hook in Web.pm, and the
# subtlety that broke production lives in that one line rather than in the
# escaper.
#
# The API serializer in Web.pm picks its branch on `exists $tokens->{results}`.
# With the key it emits `to_json $tokens->{results}`; without it, it walks the
# ResultSets and serializes the whole token hash. /api/v1/search/node forwards
# to a handler that passes no `results` token at all, so it has always needed
# the second branch.
#
# 4fb07cc8 assigned to $tokens->{results} unconditionally. Assignment
# autovivifies, so every render gained the key, the serializer took the first
# branch, and node search answered `null`. Reported as #1649 against 2.105001.
#
# xt/41-script-json-escape.t covers escape_for_script_context() as a function
# and passed throughout, because the function was never wrong. What needed
# covering was its effect on the token hash, which is what this file asserts.

use Test::More 0.88;

BEGIN {
    use_ok( 'App::Netdisco::Util::Web', 'escape_results_token' );
}

subtest 'escapeResultsToken__a_token_hash_without_results__does_not_gain_the_key' => sub {
    my $tokens = { ips => 'rs', sightings => 'rs', netbios => 'rs' };
    escape_results_token($tokens);

    ok( !exists $tokens->{results},
      'no "results" key is created, so the API serializer still walks the tokens' );
    is_deeply( [sort keys %$tokens], [qw/ips netbios sightings/],
      'the hash is otherwise untouched' );
};

subtest 'escapeResultsToken__a_json_string__is_escaped_for_the_script_context' => sub {
    my $tokens = { results => '[{"name":"a</script><script>evil()</script>"}]' };
    escape_results_token($tokens);

    unlike( $tokens->{results}, qr{</},
      'no "</" survives to be seen by the HTML parser' );
    like( $tokens->{results}, qr/\\u003C/,
      'the "<" is emitted as its JSON escape' );
};

subtest 'escapeResultsToken__results_holding_a_reference__is_left_alone' => sub {
    # The report and CSV paths pass an arrayref, which the API serializer
    # encodes itself. Escaping is a string operation and must not reach it.
    my $rows = [ { name => 'a<b' } ];
    my $tokens = { results => $rows };
    escape_results_token($tokens);

    is( $tokens->{results}, $rows, 'the same reference is still in place' );
    is( $tokens->{results}[0]{name}, 'a<b', 'its contents are unchanged' );
};

subtest 'escapeResultsToken__results_present_but_undef__keeps_the_key' => sub {
    # A handler that passes results => undef has chosen the first serializer
    # branch. Deleting the key here would change its answer.
    my $tokens = { results => undef };
    escape_results_token($tokens);

    ok( exists $tokens->{results}, 'the key survives' );
    is( $tokens->{results}, undef, 'and is still undef' );
};

subtest 'escapeResultsToken__something_other_than_a_hashref__is_a_no_op' => sub {
    my $not_tokens = 'scalar';
    is( escape_results_token($not_tokens), $not_tokens,
      'a non-hashref is returned unchanged rather than dying' );
};

done_testing;
