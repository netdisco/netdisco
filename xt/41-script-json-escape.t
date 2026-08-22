#!/usr/bin/env perl

# The report and search templates embed their result set as a JavaScript
# literal inside a <script> element:
#
#     "data": [% results | none %],
#
# Inside a script element the HTML parser stops at the first "</", even one
# sitting inside a JavaScript string, so any "<" that reaches the page from
# stored data can end the element early and turn the rest of the payload into
# live markup. escape_for_script_context() removes that class of problem by
# emitting every "<" as its JSON unicode escape, which JSON.parse and every
# JavaScript engine read back as "<", leaving the data identical.
#
# U+2028 and U+2029 are escaped for a different reason. This JSON is emitted as
# JavaScript source rather than parsed from a string, and both characters are
# line terminators there.
#
# The payloads below are built with Dancer's to_json, not JSON::PP's
# encode_json, because that is what the route handlers call and the two differ
# in a way that matters here: to_json returns a character string holding a
# literal U+2028, while encode_json returns UTF-8 bytes holding e2 80 a8. A
# test written against encode_json would assert on a character that is not
# there and pass without checking anything.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;

BEGIN {
    use_ok( 'App::Netdisco::Util::Web', 'escape_for_script_context' );
}

# Dancer's DSL lives in its own package because it exports a `pass` that
# collides with Test::More's and Perl warns about the prototype mismatch.
{
    package JSONish;
    use Dancer ':syntax';
    sub enc { return Dancer::to_json(@_) }
    sub dec { return Dancer::from_json(@_) }
}

sub to_json   { JSONish::enc(@_) }
sub from_json { JSONish::dec(@_) }

subtest 'escapeForScriptContext__a_closing_script_tag__cannot_end_the_element' => sub {
    my $json = to_json( [ { name => 'router-1</script><script>evil()</script>' } ] );
    my $safe = escape_for_script_context($json);

    unlike( $safe, qr{</}, 'no "</" survives to be seen by the HTML parser' );
    like( $safe, qr/\\u003C/, 'the "<" is emitted as its JSON escape' );
};

subtest 'escapeForScriptContext__an_html_comment_open__is_also_neutralised' => sub {
    # <!-- and <script inside a script element drive the parser into its
    # escaped states, so escaping every "<" rather than only "</" is what makes
    # the rule complete.
    my $safe = escape_for_script_context( to_json( [ { name => '<!--<script>' } ] ) );

    unlike( $safe, qr/<!--/, 'no comment opener survives' );
    unlike( $safe, qr/<script/i, 'no script opener survives' );
};

subtest 'escapeForScriptContext__any_payload__parses_back_to_the_same_data' => sub {
    # The whole approach rests on this. If escaping is visible to the consumer,
    # every table on every page renders wrong.
    my $data = [
        { name => 'router-1</script>', descr => '<!-- x -->', vlan => 42 },
        { name => "line\x{2028}separator", descr => "para\x{2029}separator" },
        { name => 'plain', descr => undef },
    ];
    my $json = to_json($data);

    is_deeply( from_json( escape_for_script_context($json) ), $data,
        'the escaped JSON decodes to exactly the original structure' );
};

subtest 'escapeForScriptContext__javascript_line_terminators__are_escaped' => sub {
    my $json = to_json( [ { name => "a\x{2028}b\x{2029}c" } ] );

    ok( $json =~ /\x{2028}/, 'to_json really does leave a literal U+2028 in place' )
        or diag 'if this fails the assertions below prove nothing';

    my $safe = escape_for_script_context($json);
    unlike( $safe, qr/\x{2028}/, 'no raw U+2028 survives' );
    unlike( $safe, qr/\x{2029}/, 'no raw U+2029 survives' );
};

subtest 'escapeForScriptContext__values_that_are_not_json_strings__pass_through' => sub {
    is( escape_for_script_context(undef), undef, 'undef is returned unchanged' );

    my $ref = [ 1, 2, 3 ];
    is( escape_for_script_context($ref), $ref,
        'a reference is returned unchanged, not stringified' );

    is( escape_for_script_context(''), '', 'the empty string is returned unchanged' );
};

subtest 'webApp__the_results_token__is_escaped_before_the_template_sees_it' => sub {
    # The function is only half the fix. Assert the hook that calls it exists,
    # so deleting the hook fails a test rather than silently reopening this.
    use FindBin;
    use File::Spec::Functions qw(catdir catfile updir);

    my $path = catfile( catdir( $FindBin::Bin, updir() ),
        qw(lib App Netdisco Web.pm) );
    my $web = do {
        open my $fh, '<', $path or die "cannot read $path: $!";
        local $/; <$fh>;
    };

    like( $web, qr/hook \s+ '?before_template'? .*? escape_for_script_context/xs,
        'a before_template hook passes the results token through the escaper' );
    like( $web, qr/\$tokens->\{results\}/,
        'and it is the results token that is escaped' );
};

done_testing;
