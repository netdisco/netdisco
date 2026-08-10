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
    # Relative, so it resolves under a path-prefixed deployment and from both
    # /swagger-ui/ and /swagger-ui/index.html.
    like $html, qr{\burl:\s*["']\.\./swagger\.json["']},
        'the default spec URL is ../swagger.json';
};

subtest 'swagger_ui_index__shipped_page__disables_the_online_validator' => sub {
    # On by default, and it sends the definition URL to a Swagger-hosted service
    # on every page load, which for most deployments publishes an internal
    # hostname. It cannot be caught in local testing: the badge suppresses itself
    # when the URL contains localhost or 127.0.0.1.
    like $html, qr{\bvalidatorUrl:\s*null\b},
        'validatorUrl is null';
};

subtest 'swagger_ui_index__shipped_page__gates_the_query_before_construction' => sub {
    # Ordering is the whole mechanism, not an incidental detail. The bundle reads
    # window.location.search when SwaggerUIBundle runs, so a gate placed after
    # that call cannot remove anything: the request has already left.
    # Anchored on the CALL, not the bare identifier. The page's comments name
    # replaceState too, and an earlier version of this test matched one of them,
    # so deleting the real call left it passing.
    my $gate      = $html =~ m{history\.replaceState\(} ? $-[0] : -1;
    my $construct = index $html, 'SwaggerUIBundle({';

    cmp_ok $gate,      '>', -1, 'the address is rewritten somewhere in the page';
    cmp_ok $construct, '>', -1, 'the bundle is constructed somewhere in the page';
    cmp_ok $gate, '<', $construct,
        'the rewrite runs before the bundle reads the query';

    # Where replaceState is unavailable the page reloads to the clean address
    # instead, and it MUST NOT fall through to construction: the poisoned query
    # is still live until the reload lands. That return is the whole safety of
    # the fallback path, so the text between the two is checked for it.
    my $fallback = $html =~ m{location\.replace\(} ? $-[0] : -1;
    cmp_ok $fallback, '>', -1, 'a reload fallback exists for missing replaceState';
    cmp_ok $fallback, '<', $construct, 'the fallback also precedes construction';
    like substr($html, $fallback, $construct - $fallback), qr{\breturn\b},
        'the fallback returns rather than falling through to construction';

    # Either polarity, because an early return and a combined boolean are both
    # correct and pinning one would fail a rewrite that is not a regression. What
    # is asserted is that origins are COMPARED at all. Whether the comparison
    # runs the right way round is not a question a grep can answer, and is
    # settled by driving the page instead.
    like $html, qr{\.origin\s*[!=]==\s*window\.location\.origin},
        'the candidate is judged by comparing origins';
    # Matches the literal JavaScript /\/swagger\.json$/ , so the backslash and
    # the dollar are both escaped for Perl rather than anchoring this pattern.
    like $html, qr{swagger\\\.json\$/},
        'the accepted path is pinned to swagger.json';
};

subtest 'swagger_ui_index__shipped_page__reads_the_parameter_without_URLSearchParams' => sub {
    # Passes before the fix as well as after, deliberately: it guards a choice a
    # later editor would naturally "tidy" into URLSearchParams. A browser lacking
    # that constructor would then throw here and render no page at all, where
    # falling through to the default degrades safely.
    # The construction, not the bare name: the page's own comment explains what
    # it avoids and why, and naming the identifier there is worth keeping.
    unlike $html, qr{new\s+URLSearchParams},
        'the query is parsed without constructing URLSearchParams';
};

done_testing;
