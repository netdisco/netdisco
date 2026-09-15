#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile updir/;
use FindBin;

# search_fuzzy refuses an empty search term, deliberately:
# DB/ResultSet/Device.pm dies "missing param to search_fuzzy" rather than
# building a query that would match the whole table. Every caller outside this
# file honours that by testing the parameter first (Web/Search.pm redirects,
# Search/Device.pm and Report/ModuleInventory.pm test before calling), but two
# typeahead handlers passed param('query') || param('term') straight in, so
# `?term=` or a missing term answered 500 with an HTML error page from an
# endpoint that advertises JSON. Measured on the public demo and on master:
# 500 for an empty or absent term, 200 for ?term=a. Netdisco's own search box
# cannot reach it, since netdisco.js sets minLength: 3, so it is external
# clients and hand-built requests that meet it.
#
# The fix is the guard this file asserts, and an empty list is the honest
# answer: an empty box means nothing was typed, not that the caller erred.
#
# What is asserted is deliberately tolerant of HOW the guard is written. For
# each typeahead handler that queries, the source between the statement that
# reads the term and the search_fuzzy call must contain an empty-list return.
# `... or return '[]';` on the assignment satisfies it, and so would a
# `return '[]' unless $q;` on the line below. What it will not accept is the
# devicename handler's pre-existing `return '[]' unless setting(...)`, which
# sits ABOVE the assignment and guards something else entirely: that line is
# why a simpler "the handler returns an empty list somewhere" assertion would
# have passed while the bug was live.
#
# THIS FILE IS A SOURCE ASSERTION for the reason xt/35-login-return-url.t
# records: these routes are require_login and the auth provider is DBIC, so
# they cannot be driven from xt. The behavioural evidence is a browser and
# curl run against both routes, recorded in the commit that added this file.

my $module = catfile( $FindBin::Bin, updir(),
    'lib', 'App', 'Netdisco', 'Web', 'TypeAhead.pm' );

my $source = do {
    open my $fh, '<', $module or die "cannot read $module: $!";
    local $/;
    <$fh>;
};

my @handlers;
while ( $source =~ m/^ajax \s+ '([^']*\/typeahead)' (.*?) ^\};$/msgx ) {
    my ( $path, $body ) = ( $1, $2 );
    push @handlers, { path => $path, body => $body };
}

my @querying = grep { $_->{body} =~ /search_fuzzy/ } @handlers;

subtest 'typeAheadRoutes__swept_from_the_module__include_the_ones_that_query' => sub {
    cmp_ok scalar(@handlers), '>=', 5, 'the typeahead handlers were parsed'
        or diag 'nothing was parsed, so every assertion below is vacuous';

    # The port and subnet handlers match their own columns and never reach
    # search_fuzzy, so its contract does not bind them and they are not
    # asserted on below.
    cmp_ok scalar(@querying), '>=', 3,
        'and three of them reach search_fuzzy, which is what needs the guard';
};

subtest 'typeAheadRoutes__given_an_empty_term__return_before_reaching_searchFuzzy' => sub {
    foreach my $handler (@querying) {
        my ($assignment) = $handler->{body} =~ m/(my \s+ \$q \s* = [^;]*;)/x;

        ok defined $assignment, "$handler->{path} reads its term into \$q"
            or next;

        my $start = index $handler->{body}, $assignment;
        my $query = index $handler->{body}, 'search_fuzzy';
        my $between = substr $handler->{body}, $start, ( $query - $start );

        like $between, qr/return \s+ '\[\]'/x,
            "$handler->{path} answers an empty term with an empty list"
            or diag "$handler->{path} passes an unchecked \$q to search_fuzzy, "
                  . 'which dies and becomes a 500';
    }
};

subtest 'typeAheadRoutes__answering_early__have_already_declared_JSON' => sub {
    # The early return ships a body, so the content type has to be set above
    # the guard rather than below the query. Dancer::Plugin::Ajax otherwise
    # defaults it to text/xml, and nothing in share/config.yml overrides that.
    foreach my $handler (@querying) {
        my $guard = index $handler->{body}, "return '[]'";
        next if $guard < 0;

        my $declared = index $handler->{body}, "content_type 'application/json'";
        cmp_ok $declared, '>=', 0,
            "$handler->{path} declares JSON";
        cmp_ok $declared, '<', $guard,
            "$handler->{path} declares JSON before its first empty-list return";
    }
};

done_testing;
