#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Find;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;

# bootstrap5-toggle renamed these two attributes. It still honours the old
# names, so nothing looks wrong and only the browser console says so.

my %renamed = ( 'data-on' => 'data-onlabel', 'data-off' => 'data-offlabel' );

my $views = catdir( $FindBin::Bin, updir(), qw/share views/ );

my @templates;
find( sub { push @templates, $File::Find::name if -f and /\.tt$/ }, $views );

ok( scalar @templates, 'the templates were found' )
  or BAIL_OUT( "nothing to scan under $views" );

my @deprecated;
foreach my $file (@templates) {
    my $source = do {
        open my $fh, '<', $file or die "cannot read $file: $!";
        local $/;
        <$fh>;
    };

    foreach my $old ( sort keys %renamed ) {
        # The word boundary matters: data-onstyle and data-onvalue are current.
        while ( $source =~ m/\b\Q$old\E=/g ) {
            my $line = 1 + ( substr( $source, 0, $-[0] ) =~ tr/\n// );
            my $relative = $file;
            $relative =~ s{^.*/share/}{share/};
            push @deprecated, "$relative:$line uses $old, rename to $renamed{$old}";
        }
    }
}

is_deeply( \@deprecated, [], 'no template uses a renamed toggle attribute' )
  or diag( "each of these warns in the browser console:\n  "
         . join( "\n  ", @deprecated ) );

done_testing;
