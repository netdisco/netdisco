#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Find;
use File::Spec::Functions qw/catdir updir/;
use FindBin;

# A row's delete control is a default button carrying a red trash icon. On a
# btn-danger button the icon is red on red and all but disappears.
#
# The Confirm button inside each delete modal is btn-danger and stays that way:
# it carries text, not the icon, so it is not matched here.

my $views = catdir( $FindBin::Bin, updir(), qw/share views/ );

my @templates;
find( sub { push @templates, $File::Find::name if -f and /\.tt$/ }, $views );

ok( scalar @templates, 'the templates were found' )
  or BAIL_OUT( "nothing to scan under $views" );

my @red_on_red;
foreach my $file (@templates) {
    my $source = do {
        open my $fh, '<', $file or die "cannot read $file: $!";
        local $/;
        <$fh>;
    };

    while ( $source =~ m{(<button\b[^>]*>)(.*?)</button>}gs ) {
        my ($open_tag, $content) = ($1, $2);
        # Taken before the matches below, which reset it.
        my $offset = $-[0];
        next unless $content =~ m/fa-trash-can/;
        my ($classes) = $open_tag =~ m/class="([^"]*)"/;
        next unless defined $classes;
        next unless $classes =~ m/(?:^|\s)btn-danger(?:\s|$)/;

        my $relative = $file;
        $relative =~ s{^.*/share/}{share/};
        my $line = 1 + ( substr( $source, 0, $offset ) =~ tr/\n// );
        push @red_on_red, "$relative:$line";
    }
}

is_deeply( \@red_on_red, [],
    'no delete button hides its icon against its own background' )
  or diag( "these draw a red trash icon on a red button:\n  "
         . join( "\n  ", @red_on_red ) );

done_testing;
