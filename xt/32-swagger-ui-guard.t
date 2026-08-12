#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile updir/;
use FindBin;

# This file asserts the CONTENT of the shipped Swagger UI page, not its
# behaviour, and the distinction matters when reading a pass.
#
# The failure it guards is a re-vendor: dropping in a fresh upstream index.html
# reverts every local change below at once and silently, which is exactly how the
# petstore default arrived in the first place. A content assertion catches that.
#
# It cannot prove the page is safe, because it shares its input with the code it
# checks. The behavioural evidence is a browser driven against the page with
# off-host requests blocked and recorded, and it does not live in this suite,
# because the distribution has no working JavaScript test path.

my $page = catfile( $FindBin::Bin, updir(),
    'share', 'public', 'swagger-ui', 'index.html' );

my $html = do {
    open my $fh, '<', $page or die "cannot read $page: $!";
    local $/;
    <$fh>;
};

subtest 'swagger_ui_index__shipped_page__names_no_external_spec_host' => sub {
    unlike $html, qr{https?://[^"'\s]*\bswagger\.io}i,
        'no swagger.io host appears anywhere in the page';
};

subtest 'swagger_ui_index__shipped_page__defaults_to_own_swagger_json' => sub {
    # Two halves, because the default is no longer a literal in the constructor.
    # The page sanitises any ?url= into specUrl and falls back to its own
    # definition; asserting the literal alone would pass on a page that computed
    # the value and then handed the bundle something else.
    #
    # Relative, so it resolves under a path-prefixed deployment and from both
    # /swagger-ui/ and /swagger-ui/index.html.
    like $html, qr{\|\|\s*["']\.\./swagger\.json["']},
        'the fallback spec URL is ../swagger.json';
    like $html, qr{\burl:\s*specUrl\b},
        'the bundle is given the sanitised value, not the raw parameter';
};

subtest 'swagger_ui_index__shipped_page__disables_the_online_validator' => sub {
    # On by default, and it sends the definition URL to a Swagger-hosted service
    # on every page load, which for most deployments publishes an internal
    # hostname. It cannot be caught in local testing: the badge suppresses itself
    # when the URL contains localhost or 127.0.0.1.
    like $html, qr{\bvalidatorUrl:\s*null\b},
        'validatorUrl is null';
};

subtest 'swagger_ui_index__shipped_page__leaves_query_configuration_off' => sub {
    # This is what the whole arrangement rests on from 4.1.3 onward. With
    # queryConfigEnabled the bundle reads ?url= itself, and ?configUrl= and every
    # other key with it, at which point the sanitiser below is decoration: the
    # bundle has already taken the attacker's value. The default is off, so the
    # assertion is that nothing turns it on.
    unlike $html, qr{queryConfigEnabled\s*:\s*true},
        'query configuration is not enabled';
};

subtest 'swagger_ui_index__shipped_page__sanitises_the_query_before_construction' => sub {
    # Ordering is the whole mechanism, not an incidental detail: the value has to
    # be judged before it reaches the constructor, since the bundle fetches
    # whatever url it is handed. Anchored on the CALL rather than the bare name,
    # because the page's own comments discuss the sanitiser and an earlier
    # version of this test matched a comment, so deleting the real call left it
    # passing.
    my $sanitise  = $html =~ m{specUrl\s*=\s*sameOriginSpecUrl\(} ? $-[0] : -1;
    my $construct = index $html, 'SwaggerUIBundle({';

    cmp_ok $sanitise,  '>', -1, 'the parameter is passed through the sanitiser';
    cmp_ok $construct, '>', -1, 'the bundle is constructed somewhere in the page';
    cmp_ok $sanitise, '<', $construct,
        'the sanitiser runs before the bundle is given a url';

    # Either polarity, because an early return and a combined boolean are both
    # correct and pinning one would fail a rewrite that is not a regression. What
    # is asserted is that origins are COMPARED at all. Whether the comparison
    # runs the right way round is not a question a grep can answer, and is
    # settled by driving the page instead.
    like $html, qr{\.origin\s*[!=]==\s*window\.location\.origin},
        'the candidate is judged by comparing origins';

    # Same origin alone would accept any JSON an attacker can get served from
    # this host, so the path is pinned too. Written against endsWith rather than
    # a regular expression, which is what the page uses.
    like $html, qr{\.pathname\.endsWith\(\s*["']/swagger\.json["']\s*\)},
        'the accepted path is pinned to /swagger.json';

    # The candidate is resolved against the page before either check. Without
    # this, "/\evil.com/x.json" reads as relative to a string match while the URL
    # parser treats the backslash as a separator and resolves it to another
    # origin.
    like $html, qr{new\s+URL\(\s*candidate\s*,\s*window\.location\.href\s*\)},
        'the candidate is resolved against the page before it is judged';
};

# There is no subtest asserting the query is parsed without URLSearchParams, and
# its absence is deliberate rather than an oversight. Against 3.20.3 it guarded a
# hand-rolled parse that a later editor would naturally tidy into the
# constructor, which on a browser without it would throw and render nothing. That
# reasoning died with the upgrade: Swagger UI 5 cannot run on such a browser at
# all, so the page uses URLSearchParams and there is no safer alternative to
# protect.

done_testing;
