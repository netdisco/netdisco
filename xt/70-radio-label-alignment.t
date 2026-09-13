#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Find;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;

# The radio's circle is the label's ::before with no top and its dot the ::after
# with one. A label wrapping a form control is taller than its text, so
# centering is what lines all three up, and it has to reach both pseudo-elements.

my $views = catdir( $FindBin::Bin, updir(), qw/share views/ );

my @templates;
find( sub { push @templates, $File::Find::name if -f and /\.tt$/ }, $views );

ok( scalar @templates, 'the templates were found' )
  or BAIL_OUT( "nothing to scan under $views" );

my @unaligned;
foreach my $file (@templates) {
    my $source = do {
        open my $fh, '<', $file or die "cannot read $file: $!";
        local $/;
        <$fh>;
    };

    while ( $source =~ m{<div\b[^>]*class="[^"]*\bradio\b[^"]*"[^>]*>(.*?)</div>}gs ) {
        my $block = $1;
        my $offset = $-[0];

        while ( $block =~ m{(<label\b[^>]*>)(.*?)</label>}gs ) {
            my ($open_tag, $content) = ($1, $2);
            next unless $content =~ m/<(?:input|select|textarea)\b/;
            next if $open_tag =~ m/class="[^"]*\bnd_radio-with-field\b[^"]*"/;

            my $relative = $file;
            $relative =~ s{^.*/share/}{share/};
            my $line = 1 + ( substr( $source, 0, $offset ) =~ tr/\n// );
            push @unaligned, "$relative:$line";
        }
    }
}

is_deeply( \@unaligned, [],
    'every radio label wrapping a field carries the class that aligns it' )
  or diag( "these leave the label's text low against its circle:\n  "
         . join( "\n  ", @unaligned ) );

my $css = do {
    my $path = catfile( $FindBin::Bin, updir(), qw/share public css netdisco.css/ );
    open my $fh, '<', $path or die "cannot read $path: $!";
    local $/;
    <$fh>;
};

like( $css, qr/\.nd_radio-with-field\s*\{[^}]*align-items:\s*center/,
    'the class is defined' );

# awesome-bootstrap-checkbox sets display on `.radio label`, which outranks a
# lone class, so the rule above does nothing without the element in it.
like( $css, qr/label\.nd_radio-with-field\s*\{/,
    'the selector outranks the theme it overrides' );

foreach my $part (qw/before after/) {
    like( $css, qr/label\.nd_radio-with-field::$part\s*\{[^}]*\btop:/,
        "the ::$part is placed rather than left where the contents put it" );
}

done_testing;
