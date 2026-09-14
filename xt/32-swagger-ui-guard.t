#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile catdir updir/;
use FindBin;

# This file asserts the CONTENT of netdisco's Swagger UI configuration, not its
# behaviour, and the distinction matters when reading a pass: it shares its
# input with the code it checks. The sanitiser is EXECUTED by
# xt/js/swagger-spec-url.test.js, which is the stronger evidence.

my $root = catdir( $FindBin::Bin, updir() );

my $script = catfile( $root, 'share', 'public', 'javascripts', 'netdisco-swagger.js' );
my $view   = catfile( $root, 'share', 'views', 'swagger-ui.tt' );
my $drop   = catdir( $root, 'share', 'public', 'swagger-ui' );

my $slurp = sub {
    my $path = shift;
    open my $fh, '<', $path or die "cannot read $path: $!";
    local $/;
    <$fh>;
};

my $js   = $slurp->($script);
my $html = $slurp->($view);

subtest 'swagger_ui_drop__the_vendored_directory__carries_no_entry_point' => sub {
    # swagger-ui-dist splits its entry point into index.html, index.css and
    # swagger-initializer.js, the last of those carrying the petstore URL as its
    # default. The drop is a curated subset that has never included them, and
    # netdisco serves share/views/swagger-ui.tt instead.
    #
    # Copying the whole dist in fails here, and the fix is to drop those three
    # again rather than to edit them.
    foreach my $name (qw/index.html index.css swagger-initializer.js/) {
        ok !-e catfile( $drop, $name ),
            "share/public/swagger-ui/$name is not vendored";
    }

    ok -f $view, 'share/views/swagger-ui.tt is the entry point instead';
};

subtest 'swagger_ui_config__shipped_files__name_no_external_spec_host' => sub {
    unlike $js,   qr{https?://[^"'\s]*\bswagger\.io}i,
        'no swagger.io host appears in the configuration';
    unlike $html, qr{https?://[^"'\s]*\bswagger\.io}i,
        'no swagger.io host appears in the page';
};

subtest 'swagger_ui_config__shipped_script__defaults_to_own_swagger_json' => sub {
    # Two halves, because the default is not a literal in the constructor. The
    # script sanitises any ?url= into specUrl and falls back to its own
    # definition; asserting the literal alone would pass on a file that computed
    # the value and then handed the bundle something else.
    #
    # Relative, so it resolves under a path-prefixed deployment.
    like $js, qr{DEFAULT_SPEC_URL\s*=\s*["']\.\./swagger\.json["']},
        'the fallback spec URL is ../swagger.json';
    like $js, qr{\burl:\s*specUrl\b},
        'the bundle is given the sanitised value, not the raw parameter';
};

subtest 'swagger_ui_config__shipped_script__disables_the_online_validator' => sub {
    # On by default, and it sends the definition URL to a Swagger-hosted service
    # on every page load, which for most deployments publishes an internal
    # hostname. It cannot be caught in local testing: the badge suppresses itself
    # when the URL contains localhost or 127.0.0.1.
    like $js, qr{\bvalidatorUrl:\s*null\b},
        'validatorUrl is null';
};

subtest 'swagger_ui_config__shipped_script__leaves_query_configuration_off' => sub {
    # This is what the whole arrangement rests on from 4.1.3 onward. With
    # queryConfigEnabled the bundle reads ?url= itself, and ?configUrl= and every
    # other key with it, at which point the sanitiser is decoration: the bundle
    # has already taken the attacker's value. The default is off, so the
    # assertion is that nothing turns it on.
    unlike $js, qr{queryConfigEnabled\s*:\s*true},
        'query configuration is not enabled';
};

subtest 'swagger_ui_config__shipped_script__sanitises_before_construction' => sub {
    # Ordering is the whole mechanism, not an incidental detail: the value has to
    # be judged before it reaches the constructor, since the bundle fetches
    # whatever url it is handed. Anchored on the CALL rather than the bare name,
    # because the file's own comments discuss the sanitiser and an earlier
    # version of this test matched a comment, so deleting the real call left it
    # passing.
    my $sanitise  = $js =~ m{sameOriginSpecUrl\(\s*requested} ? $-[0] : -1;
    my $construct = index $js, 'SwaggerUIBundle(';

    cmp_ok $sanitise,  '>', -1, 'the parameter is passed through the sanitiser';
    cmp_ok $construct, '>', -1, 'the bundle is constructed somewhere in the file';
    cmp_ok $sanitise, '<', $construct,
        'the sanitiser runs before the bundle is given a url';

    # Either polarity: an early return and a combined boolean are both correct.
    # This asserts only that origins are COMPARED. Which way round is settled by
    # xt/js/swagger-spec-url.test.js against a real off-origin candidate.
    like $js, qr{\.origin\s*[!=]==\s*new\s+URL\(\s*base\s*\)\.origin},
        'the candidate is judged by comparing origins';

    # Same origin alone would accept any JSON an attacker can get served from
    # this host, so the path is pinned too. Written against endsWith rather than
    # a regular expression, which is what the file uses.
    like $js, qr{\.pathname\.endsWith\(\s*["']/swagger\.json["']\s*\)},
        'the accepted path is pinned to /swagger.json';

    # The candidate is resolved against the page before either check. Without
    # this, "/\evil.com/x.json" reads as relative to a string match while the URL
    # parser treats the backslash as a separator and resolves it to another
    # origin.
    like $js, qr{new\s+URL\(\s*candidate\s*,\s*base\s*\)},
        'the candidate is resolved against the page before it is judged';
};

subtest 'swagger_ui_view__the_page__loads_the_bundle_before_our_script' => sub {
    # netdisco-swagger.js reads SwaggerUIBundle at load time, so loading ours
    # first leaves the UI silently unstarted. Anchored on the script tag: the
    # template's comment names the file too.
    my $bundle = $html =~ m{<script[^>]+src="[^"]*swagger-ui-bundle\.js} ? $-[0] : -1;
    my $ours   = $html =~ m{<script[^>]+src="[^"]*netdisco-swagger\.js}  ? $-[0] : -1;

    cmp_ok $bundle, '>', -1, 'the page loads the vendored bundle';
    cmp_ok $ours,   '>', -1, 'the page loads netdisco-swagger.js';
    cmp_ok $bundle, '<', $ours, 'the bundle is loaded first';
};

# Nothing here guards the use of URLSearchParams. Swagger UI 5 cannot run on a
# browser lacking it, so there is no safer alternative to protect.

done_testing;
