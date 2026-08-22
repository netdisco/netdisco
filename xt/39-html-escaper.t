#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use File::Spec::Functions qw(catdir catfile updir);
use File::Find;
use Test::More;

# The HTML escaper for SNMP-sourced values in DataTables render callbacks
# is DataTable.util.escapeHtml, from the DataTables bundle already loaded
# on every page. he.js was removed because it duplicated that job at a
# cost of 26,948 gzipped bytes per page load and threw a TypeError on any
# non-string where the DataTables escaper passes them through.
#
# CONSTRAINT for future call sites: DataTable.util.escapeHtml escapes
# < > & " but NOT the single quote, where he.encode did. Every current
# insertion point is HTML text content, so this is safe today, but an
# escaped value placed inside a single-quoted HTML attribute would be
# unsafe. Do not put escaped values in single-quoted attributes.
#
# SCOPE: this guard checks for the specific library and call site
# removed here, by name (he.js, he.encode). It is not a general
# "only DataTable.util.escapeHtml is permitted" guard. A differently
# named duplicate escaper vendored later, for example html-entities.js
# exposing entities.encode(), would defeat every assertion below and
# would not be caught by this test.

my $root = catdir( $FindBin::Bin, updir() );

# Walk the tree in Perl rather than shelling out to grep, so a failed
# or unrun search cannot silently read as an empty, passing result.
my @he_calls;
find(
    sub {
        return unless -f $_;
        open my $fh, '<:raw', $_
            or die "cannot read $File::Find::name: $!";
        local $/;
        my $content = <$fh>;
        push @he_calls, $File::Find::name if $content =~ /he\.encode/;
    },
    catdir( $root, 'share' )
);
is( scalar @he_calls, 0, 'no he.encode call sites remain under share/' )
    or diag "found in: @he_calls";

ok( ! -e catfile( $root, qw(share public javascripts he.js) ),
    'he.js is not shipped' );

my $main_tt = do {
    my $path = catfile( $root, qw(share views layouts main.tt) );
    open my $fh, '<', $path or die "cannot read $path: $!";
    local $/; <$fh>;
};
unlike( $main_tt, qr{/he\.js}, 'main.tt does not load he.js' );

my $manifest = do {
    my $path = catfile( $root, 'MANIFEST' );
    open my $fh, '<', $path or die "cannot read $path: $!";
    local $/; <$fh>;
};
unlike( $manifest, qr{^share/public/javascripts/he\.js$}m,
    'MANIFEST does not list he.js' );

done_testing;
