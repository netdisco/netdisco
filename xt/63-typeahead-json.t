#!/usr/bin/env perl

use strict;
use warnings;

# The device name typeahead is the only route that ran its labels through
# encode_entities. The menu that consumed them escaped a second time, so a
# device named with an ampersand read back with the entity showing. The menu
# now writes text nodes, which escapes nothing and needs nothing escaped, so
# the route hands over the name as the database holds it.

use Test::More 0.88;
use FindBin;

open my $fh, '<', "$FindBin::RealBin/../lib/App/Netdisco/Web/TypeAhead.pm"
  or die "TypeAhead.pm: $!";
my $source = do { local $/; <$fh> };
close $fh;

unlike $source, qr/encode_entities/,
  'no typeahead route escapes a label into its JSON';
unlike $source, qr/use HTML::Entities/,
  'the escaper is no longer imported';

done_testing;
