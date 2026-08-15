#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Find;
use File::Spec::Functions qw/catdir updir/;
use FindBin;

# A Dancer handler answers with its last expression, so a route that renders a
# template and then evaluates something else throws the rendered page away.
#
# c9492899 ("fix return on ajax", 2026-06-28) added `return '';` to ten
# handlers. Eight are control routes, where an empty body is the correct
# answer and the line is right. Two landed on content routes,
# /ajax/content/admin/pseudodevice and /ajax/content/admin/duplicatedevices,
# where the rendered template IS the response, so both panes answered 200 with
# zero bytes and netdisco.js substituted its generic "No matching records."
# alert whatever the database held. Measured against a seeded database before
# the fix: 0 bytes from each, against 6945 bytes from
# /ajax/content/admin/jobqueue, whose handler that commit never touched.
#
# The two invariants below are general rather than a list of the two files,
# because the mistake is general: a content route renders, a control route
# acts. Either half of it can be made again in any of the plugins.
#
# THIS FILE IS A SOURCE ASSERTION, and as in xt/35-login-return-url.t the
# reason is the database and only the database. The app loads in a test
# process and Dancer::Test works, but both routes are `require_role admin` and
# the auth provider is DBIC, which setting `no_auth` does not bypass. So the
# responses themselves cannot be driven from here. Do not close that gap by
# finding a database at run time and skipping without one: a developer machine
# has one and CI does not, so the test would look green here and never run
# upstream.

my $lib = catdir( $FindBin::Bin, updir(), 'lib' );

my @modules;
find( sub { push @modules, $File::Find::name if -f && /\.pm$/ }, $lib );

my ( @content_routes, @other_routes, $declared );

foreach my $module ( sort @modules ) {
    my $source = do {
        open my $fh, '<', $module or die "cannot read $module: $!";
        local $/;
        <$fh>;
    };

    $declared += () = $source =~ m/^ajax \s+ '/gmx;

    # Handlers are declared at column 0 and close with `};` on its own line,
    # which is what bounds a body. The count assertion below is what makes
    # that safe to rely on: a body that stopped early would leave the totals
    # disagreeing rather than quietly passing on a truncated last statement.
    while ( $source =~ m/^ajax \s+ '([^']+)' (.*?) ^\};$/msgx ) {
        # Copied out before anything else runs a regex: the hash constructor
        # below would otherwise read $1 and $2 after the module name's own
        # substitution had reset them.
        my ( $path, $body ) = ( $1, $2 );

        my $route = {
            path   => $path,
            body   => $body,
            module => ( $module =~ s{^.*/lib/}{lib/}r ),
        };

        push @{ $route->{path} =~ m{^/ajax/content/} ? \@content_routes : \@other_routes },
          $route;
    }
}

subtest 'ajaxRoutes__swept_from_lib__are_all_parsed_to_their_closing_brace' => sub {
    cmp_ok $declared, '>=', 10, 'the sweep found ajax routes at all'
        or diag 'nothing was parsed, so every assertion below is vacuous';
    is scalar(@content_routes) + scalar(@other_routes), $declared,
        'every declared handler was parsed, none truncated or missed';
    cmp_ok scalar(@content_routes), '>=', 10,
        'and enough of them are content routes to be worth asserting on';

    # The two the regression landed on. If either is renamed, this file needs
    # a fresh look rather than a quiet pass on the routes that remain.
    my %by_path = map { $_->{path} => 1 } @content_routes;
    ok $by_path{'/ajax/content/admin/pseudodevice'},
        'the pseudo device pane is among them';
    ok $by_path{'/ajax/content/admin/duplicatedevices'},
        'and so is the duplicate devices pane';
};

subtest 'ajaxContentRoutes__having_rendered_a_template__answer_with_it' => sub {
    foreach my $route ( sort { $a->{path} cmp $b->{path} } @content_routes ) {
        my @statements = grep { /\S/ } split /\n/, $route->{body};
        my $last = $statements[-1] // '';
        $last =~ s/^\s+//;

        like $route->{body}, qr/\btemplate\b/,
            "$route->{path} renders a template";
        unlike $last, qr/^ return \s+ (?: '' | "" ) \s* ; /x,
            "$route->{path} answers with that template, not an empty string"
            or diag "$route->{module} discards its rendered page";
    }
};

subtest 'ajaxControlRoutes__which_act_rather_than_render__call_no_template' => sub {
    # The other half of c9492899, and the reason its eight remaining empty
    # returns must be left alone: a route that renders nothing has nothing to
    # discard, so `return '';` there is the response rather than a bug.
    foreach my $route ( sort { $a->{path} cmp $b->{path} } @other_routes ) {
        unlike $route->{body}, qr/\btemplate\b/,
            "$route->{path} renders nothing, so an empty body is its answer";
    }
};

done_testing;
