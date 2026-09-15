#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;

# The Swagger UI entry point, driven as requests rather than asserted as source.
#
# This is a BEHAVIOURAL test, which xt/32-swagger-ui-guard.t deliberately is
# not: that file asserts the content of the shipped index.html and says so in
# its own header. The two are complementary and neither replaces the other.
#
# Request-level testing is possible here where it is not for most of netdisco,
# and the reason is narrow: these routes carry no `require_login`, so nothing
# reaches the DBIC auth provider, which is the thing that puts protected routes
# out of reach from xt (see the header of xt/35-login-return-url.t). No database
# is touched and no environment variables are needed. `use App::Netdisco::Web`
# is what registers the routes; `use App::Netdisco` alone leaves every path 404.
#
# What is being guarded:
#
# /swagger-ui once redirected to /swagger-ui/?url=/swagger.json, because the
# 3.20.3 page needed telling where its definition lived. Since the 5.x upgrade
# the page resolves its own (sameOriginSpecUrl(requested) || '../swagger.json'),
# so the parameter said nothing the page did not already know.
#
# THE TRAP, and the reason this file exists rather than a one-line diff:
# /swagger-ui/ used to answer `params->{url} or redirect .../swagger-ui`. Drop
# the parameter from the first route and leave that guard, and the two routes
# redirect to each other for as long as the browser will follow. The two lines
# move together or not at all, and the loop test below is what says so.

# ON THE DATABASE, because this file is the only one in xt/ that opens a
# connection and that deserves an explanation rather than a surprise.
#
# Loading App::Netdisco::Web reaches a database: Web.pm:222 evals
# schema('netdisco') to read the session cookie key. It connects and emits a
# "DB is currently unversioned" warning both on a developer machine and in CI,
# whose netdisco/netdisco:latest-backend container carries its own postgres.
#
# **A failure there would also be fine, and that is the shipped code's design
# rather than luck**: the call is wrapped in an eval whose whole purpose is to
# tolerate the key being unavailable, and Web.pm:220 substitutes a testing key
# when HARNESS_ACTIVE is set, which prove sets. So this file needs a database
# neither to pass nor to mean anything, which is what separates it from the
# protected routes xt/35 describes as out of reach.
#
# Verified by tracing the warning to its origin rather than by assuming. Do not
# "fix" the warning by pointing DANCER_ENVDIR at /dev/null: that empties the DSN
# without preventing the connection, so it changes what is connected to and not
# whether a connection is made.

use App::Netdisco;
use App::Netdisco::Web;
use Dancer ':tests';
use Dancer::Test;

my $base = Dancer::config->{plugins}{Swagger}{ui_url};

subtest 'swaggerUiConfig__as_shipped__still_hosts_the_ui_where_this_file_expects' => sub {
    # Without this the subtests below would pass vacuously against 404s if the
    # route ever moved, which is how the first draft of this file was misled.
    is $base, '/swagger-ui', 'ui_url is /swagger-ui';
};

subtest 'swaggerUiEntry__bare_path__redirects_to_the_directory_carrying_no_url_parameter' => sub {
    my $response = dancer_response( GET => $base );

    is $response->status, 302, 'the bare path redirects';

    my $location = $response->header('Location');
    is $location, "$base/", 'it points at the directory';
    unlike $location, qr/\burl=/,
        'and carries no url parameter, which the 5.x page does not need';
};

# send_file streams, so the response content is a filehandle rather than a
# string. Asserting against it directly compares a pattern to "GLOB(0x...)",
# which passes for the wrong reason on any page whose path happens to match.
sub body_of {
    my $content = shift->content;
    return $content unless ref $content eq 'GLOB';
    local $/;
    return <$content>;
}

subtest 'swaggerUiDirectory__without_a_url_parameter__serves_the_page_instead_of_redirecting' => sub {
    my $response = dancer_response( GET => "$base/" );

    is $response->status, 200,
        'the directory serves the page rather than bouncing back to the bare path';
    like body_of($response), qr/swagger-ui/i, 'and the body is the Swagger UI page';
};

subtest 'swaggerUiEntry__followed_from_the_bare_path__reaches_the_page_without_looping' => sub {
    # The regression the trap above describes, expressed as the thing a browser
    # actually does. A redirect pair that points at each other fails here by
    # exhausting the hop budget, where each route checked on its own would pass.
    my $path  = $base;
    my $hops  = 0;
    my @trail = ($path);

    while ( $hops++ < 6 ) {
        my $response = dancer_response( GET => $path );
        last if $response->status != 302;
        $path = $response->header('Location');
        push @trail, $path;
    }

    cmp_ok $hops, '<=', 3, 'settles within a couple of hops'
        or diag "redirect trail: @trail";

    my $final = dancer_response( GET => $path );
    is $final->status, 200, "the trail ends on a page: @trail";
};

subtest 'swaggerUiDirectory__given_a_url_parameter_anyway__still_serves_the_page' => sub {
    # Netdisco no longer emits one, but nothing stops a bookmark or a third
    # party from doing so, and the page's own origin checks are what make that
    # safe. Those checks and their assertions in xt/32 stay whatever this file
    # says; this only fixes that such a request is still answered normally.
    my $response = dancer_response( GET => "$base/?url=/swagger.json" );

    is $response->status, 200, 'a url parameter is accepted and ignored, not rejected';
};

done_testing;
