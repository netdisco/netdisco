#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use FindBin;

BEGIN {
  use Path::Class;
  unshift @INC, dir($FindBin::RealBin)->parent->subdir('lib')->stringify;
  $ENV{DANCER_ENVDIR} = '/dev/null';
}

# Both netmap routes key the same netmap_positions row, so they must normalise
# mapshow and depth identically, or a map draws under one key and saves under
# another. Sharing one pure function is what stops them drifting, and being pure
# it needs no database here, as with xt/45-netmap-neighbor-walk.t.

use App::Netdisco;
use App::Netdisco::Web::Plugin::Device::Neighbors;

my $norm = \&App::Netdisco::Web::Plugin::Device::Neighbors::netmap_view_params;

subtest 'netmap_view_params__an_absent_mapshow__defaults_to_depth' => sub {
    my ($mapshow, $depth) = $norm->(undef, undef, 1);
    is $mapshow, 'depth', 'absent mapshow becomes depth, as the display route always did';
    is $depth, 1, 'absent depth becomes 1';
};

subtest 'netmap_view_params__an_invalid_mapshow__defaults_to_depth' => sub {
    foreach my $bad (qw/ neighbors '' 0 sideways /) {
        my ($mapshow) = $norm->($bad, 1, 1);
        is $mapshow, 'depth', "mapshow '$bad' becomes depth";
    }
};

subtest 'netmap_view_params__a_valid_mapshow__is_left_alone' => sub {
    foreach my $ok (qw/ all cloud depth /) {
        my ($mapshow) = $norm->($ok, 1, 1);
        is $mapshow, $ok, "mapshow '$ok' survives";
    }
};

subtest 'netmap_view_params__a_device_not_in_storage__forces_all' => sub {
    foreach my $any (qw/ all cloud depth /) {
        my ($mapshow) = $norm->($any, 1, 0);
        is $mapshow, 'all',
          "mapshow '$any' becomes all when the device is not in storage, matching the display route";
    }
};

subtest 'netmap_view_params__a_non_numeric_depth__becomes_one' => sub {
    foreach my $bad ('', undef, 'abc', '1; DROP', '-2', '1.5') {
        my (undef, $depth) = $norm->('depth', $bad, 1);
        is $depth, 1, 'a depth that is not a positive integer becomes 1';
    }
    my (undef, $kept) = $norm->('depth', '3', 1);
    is $kept, 3, 'a numeric depth survives';
};

# The property that actually matters: whatever comes in, the row key is
# constructible. A route that can be handed undef here is a route that can
# silently write nothing.
subtest 'netmap_view_params__any_input__always_returns_a_usable_key' => sub {
    foreach my $mapshow (undef, '', 'all', 'cloud', 'depth', 'bogus') {
        foreach my $depth (undef, '', '0', '2', 'x') {
            my ($m, $d) = $norm->($mapshow, $depth, 1);
            like $m, qr/^(?:all|cloud|depth)$/, 'mapshow is always one of the three';
            like $d, qr/^\d+$/, 'depth is always a positive integer';
        }
    }
};

done_testing;
