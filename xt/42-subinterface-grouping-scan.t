#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile updir/;
use FindBin;

# The device Ports tab groups subinterfaces under their parent port. To do that
# it needs, for each parent name it has seen, the row carrying that name.
#
# Resolving each one by searching the whole result list re-reads every row once
# per parent, so the work grows with the ports on the device multiplied by the
# parents on it, not with the ports alone. On an access switch that is
# invisible. On a wireless controller it is the entire request: every port is
# named for an access point radio, `70:3a:0e:cd:65:16.1`, which matches the
# default `subinterfaces_match` of `(.+)\.\d+`, so nearly every port is a
# parent name. Worse, the bare `70:3a:0e:cd:65:16` port does not exist (the
# case #1479 describes), so each search reads every row and finds nothing.
#
# Measured on a 7300-port controller before the index was added: 12.98s for the
# port column alone, against 1.11s after, with byte-identical output. The
# grouping markup is unchanged: 7300 `nd_collapsible` rows either way, and
# across 120 devices that have real parented subinterfaces, in all three
# folding modes, the rendered bytes are identical.
#
# THIS FILE IS A SOURCE ASSERTION, for the reason xt/36-ajax-content-response.t
# gives at length: the route is `require_login` and the auth provider is DBIC,
# which `no_auth` does not bypass, so the response cannot be driven from a test
# process. Do not close that gap by finding a database at run time and skipping
# without one, because a developer machine has one and CI does not, so the test
# would look green here and never run upstream.
#
# The assertion is deliberately about shape rather than about the two lines it
# was written for. Any lookup that walks the result list from inside the loop
# over parents reintroduces the same cost, whatever it is spelled with.

my $file = catfile( $FindBin::Bin, updir(),
    qw/lib App Netdisco Web Plugin Device Ports.pm/ );

my $source = do {
    open my $fh, '<', $file or die "cannot read $file: $!";
    local $/;
    <$fh>;
};

# The loop bounds: from `foreach my $parent (keys %port_subinterface_count)` to
# the closing brace at that indentation. Anchoring on the loop header rather
# than on line numbers keeps this working when the file moves around it.
my ($loop) = $source =~ m/
    ^ [ ]{4} foreach \s+ my \s+ \$parent \s+ \( keys \s+ \%port_subinterface_count \)
    (.*?)
    ^ [ ]{4} \}
/msx;

ok( defined $loop,
    'the subinterface grouping loop is where this test expects it' )
  or BAIL_OUT( 'cannot find the loop in ' . $file
             . '; if it was renamed or removed, update or delete this test' );

unlike( $loop, qr/\bgrep\b/,
    'the grouping loop resolves ports without searching the result list' );

unlike( $loop, qr/\@results/,
    'the grouping loop does not touch @results at all' );

like( $source, qr/\$port_row\{\s*\$_->port\s*\}\s*=\s*\$_\s+for\s+\@results/,
    'the rows are indexed by port name in a single pass' );

like( $loop, qr/\$port_row\{\s*\$parent\s*\}/,
    'the parent port is resolved from that index' );

like( $loop, qr/\$port_row\{\s*"\$\{parent\}\.0"\s*\}/,
    'the dot-zero subinterface is resolved from that index' );

done_testing;
