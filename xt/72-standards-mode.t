#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;

# A transitional doctype puts the browser in almost standards mode, where a
# table cell's line box is measured differently. Bootstrap 5 is written for
# standards mode, and only Firefox says which one it got.

my $root = catdir( $FindBin::Bin, updir() );

my %pages = (
    'share/views/layouts/main.tt' => 'every page the app renders',
    'share/public/500.html'       => 'the page shown when the app cannot render',
);

foreach my $relative ( sort keys %pages ) {
    my $path = catfile( $root, split m{/}, $relative );
    my $source = do {
        open my $fh, '<', $path or die "cannot read $path: $!";
        local $/;
        <$fh>;
    };

    my ($doctype) = $source =~ m/^\s*(<!DOCTYPE[^>]*>)/is;
    ok( $doctype, "$relative declares a doctype" )
      or next;

    is( $doctype, '<!DOCTYPE html>',
        "$relative asks for standards mode, being $pages{$relative}" );
}

done_testing;
