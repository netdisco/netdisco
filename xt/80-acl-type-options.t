#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;

# The add form offered value="host_host" twice, once labelled "Ports on Hosts",
# so creating that type silently made a Host to Host mapping and the port
# control rule using it never applied. The golden snapshot had frozen the wrong
# markup as correct, which is why this checks the values and not the bytes.

my $template = catfile( $FindBin::Bin, updir(),
  qw/share views ajax admintask aclmanager.tt/ );

my $source = do {
    open my $fh, '<', $template or BAIL_OUT("cannot read $template: $!");
    local $/;
    <$fh>;
};

# The column has a CHECK constraint on these three and both ACLManager routes
# refuse anything else with a 400.
my @valid = qw/host host_host host_port/;

my @selects = ( $source =~ m{<select\b[^>]*\bname="acl_type"[^>]*>(.*?)</select>}gs );

is( scalar @selects, 2, 'both the add and the update acl_type selects are present' )
  or BAIL_OUT('the markup moved, so this guard is no longer looking at it');

my @which = qw/add update/;

foreach my $index ( 0 .. $#selects ) {
    my $name = $which[$index];
    my @values = ( $selects[$index] =~ m{<option\b[^>]*\bvalue="([^"]*)"}g );

    is_deeply( [ sort @values ], [ sort @valid ],
      "the $name select offers each acl_type exactly once" );

    my %seen;
    my @duplicated = grep { $seen{$_}++ } @values;
    is_deeply( \@duplicated, [],
      "the $name select repeats no acl_type value" )
      or diag("repeated: @duplicated");
}

done_testing;
