#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::CssRules qw/read_text css_rules/;

# The floated fa-lg icon makes the Update View half 28.63px tall, so a fixed
# height on the caret half left its bottom edge short. The btn-group's flex
# stretch matches the two halves only while neither sets a height.
foreach my $file ('share/public/css/netdisco.css',
                  glob 'share/public/css/themes/*.css') {
  my @heights = grep {
    $_->{selector} =~ /\.nd_sidebar-btn-drop(?:-drop)?\b/
      and $_->{property} =~ /^(?:min-|max-)?height$/
  } css_rules(read_text($file));

  is_deeply [ map { "$_->{selector} { $_->{property} }" } @heights ], [],
    "sidebarSplitButton__${file}__sets_no_height_on_either_half";
}

done_testing;
