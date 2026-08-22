#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use File::Spec::Functions qw(catdir catfile updir);
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

my $root = catdir( $FindBin::Bin, updir() );

my @he_calls = `grep -rl 'he\\.encode' $root/share`;
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
