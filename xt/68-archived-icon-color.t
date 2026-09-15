#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Find;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;

# Every archived-node marker, not the three that drifted, because what let them
# drift is that nothing held them together.
#
# text-warning sets color with !important, so a marker carrying both classes
# would pass the first check and still render in the Bootstrap color.

my $share = catdir( $FindBin::Bin, updir(), 'share' );

my @sources;
find( sub {
    return unless -f;
    return unless /\.tt$/ or /^netdisco.*\.js$/;
    push @sources, $File::Find::name;
}, $share );

ok( scalar @sources, 'the templates and shipped scripts were found' )
  or BAIL_OUT( "nothing to scan under $share" );

my @uncolored;
foreach my $file (@sources) {
    open my $fh, '<', $file or die "cannot read $file: $!";
    my $line_number = 0;
    while ( my $line = <$fh> ) {
        $line_number++;
        # Every class list on the line, so two icons on one line are both seen.
        while ( $line =~ m/class=(["'])(.*?)\1/g ) {
            my $classes = $2;
            # fa-book itself, never fa-bookmark, which is the job queue's.
            next unless $classes =~ m/(?:^|\s)fa-book(?:\s|$)/;
            next if $classes =~ m/(?:^|\s)nd_icon-archived(?:\s|$)/;
            my $relative = $file;
            $relative =~ s{^.*/share/}{share/};
            push @uncolored, "$relative:$line_number";
        }
    }
    close $fh;
}

is_deeply( \@uncolored, [],
    'every archived-node marker carries the class that colors it' )
  or diag( "these do not:\n  " . join( "\n  ", @uncolored ) );

my @still_warning;
foreach my $file (@sources) {
    open my $fh, '<', $file or die "cannot read $file: $!";
    my $line_number = 0;
    while ( my $line = <$fh> ) {
        $line_number++;
        while ( $line =~ m/class=(["'])(.*?)\1/g ) {
            my $classes = $2;
            next unless $classes =~ m/(?:^|\s)fa-book(?:\s|$)/;
            next unless $classes =~ m/(?:^|\s)text-warning(?:\s|$)/;
            my $relative = $file;
            $relative =~ s{^.*/share/}{share/};
            push @still_warning, "$relative:$line_number";
        }
    }
    close $fh;
}

is_deeply( \@still_warning, [],
    'no marker still carries text-warning' )
  or diag( "these override the marker's own class:\n  "
         . join( "\n  ", @still_warning ) );

my $css = do {
    my $path = catfile( $FindBin::Bin, updir(),
        qw/share public css netdisco.css/ );
    open my $fh, '<', $path or die "cannot read $path: $!";
    local $/;
    <$fh>;
};

like( $css, qr/\.nd_icon-archived\s*\{[^}]*color:\s*#c09853/i,
    'the marker class is defined' );

done_testing;
