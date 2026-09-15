#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile updir/;
use FindBin;

# The tree draws its elbow from two pseudo-elements: ::before is the vertical
# line down a branch and ::after the horizontal tick out to each child. The last
# child truncates the vertical one, and the two carry their own numbers, so a
# change to either leaves a stub or a gap unless both move.

my $path = catfile( $FindBin::Bin, updir(), qw/share public css bootstrap-tree.css/ );
my $css = do {
    open my $fh, '<', $path or die "cannot read $path: $!";
    local $/;
    <$fh>;
};

# Anchored: the file also has a combined `li::before, li::after` rule, which
# carries neither number and which an unanchored match finds first.
my ($tick) = $css =~ m/^ \.tree \s+ li::after \s* \{ ([^}]*) \}/xm;
ok( $tick, 'the horizontal tick is styled' ) or BAIL_OUT('no .tree li::after rule');

# `border-top` contains `top`, and comes first in the rule.
my ($tick_top)    = $tick =~ m/(?<!-) top: \s* (\d+) px/x;
my ($tick_border) = $tick =~ m/border-top: \s* (\d+) px/x;
ok( defined $tick_top && defined $tick_border,
    'the tick places itself in pixels' );

my ($last) = $css =~ m/^ \.tree \s+ li:last-child::before \s* \{ ([^}]*) \}/xm;
ok( $last, 'the last child truncates the vertical line' );

my ($height) = $last =~ m/height: \s* (\d+) px/x;
is( $height, $tick_top + $tick_border,
    'the vertical line ends exactly where the tick is drawn' )
  or diag( "the line runs to ${height}px and the tick sits at "
         . ( $tick_top + $tick_border )
         . 'px; longer leaves a stub below the last child, shorter a gap' );

done_testing;
