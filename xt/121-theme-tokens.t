#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::CssRules qw/read_text css_rules has_color_literal is_guarded/;

# A theme recolors netdisco's own elements by setting --nd-* tokens, so a
# color written anywhere else is one no theme can reach.
my %SHEETS = map { $_ => read_text("share/public/css/$_") }
  qw/netdisco.css bootstrap-tree.css/;

sub stray_colors {
  my ($name, $css) = @_;
  return map { "$name line $_->{line}: $_->{selector} { $_->{property} }" }
    grep {
      has_color_literal($_->{value})
        and $_->{property} !~ /shadow$/
        and !is_guarded($_->{selector})
        and !($_->{selector} eq ':root' and $_->{property} =~ /^--nd-/)
    } css_rules($css);
}

is_deeply [ stray_colors('control', '.nd_x { color: #123456; }') ],
  [ 'control line 1: .nd_x { color }' ],
  'strayColors__control_with_a_literal__is_reported';
is_deeply [ stray_colors('control', ':root { --nd-x: #123456; } .nd_x { color: var(--nd-x); }') ], [],
  'strayColors__control_reading_a_token__is_clean';

foreach my $name (sort keys %SHEETS) {
  is_deeply [ stray_colors($name, $SHEETS{$name}) ], [],
    "themeTokens__${name}__has_no_color_outside_tokens_and_the_base_layer";
}

my %defined = map { $_->{property} => 1 }
  grep { $_->{selector} eq ':root' and $_->{property} =~ /^--nd-/ }
  css_rules($SHEETS{'netdisco.css'});

my $netmap = read_text('share/public/javascripts/netdisco-netmap.js');
my %used;
$used{$_}++ for (join("\n", values %SHEETS) =~ m/var\((--nd-[a-z0-9-]+)/g);
$used{$_}++ for ($netmap =~ m/'(--nd-[a-z0-9-]+)'/g);

is_deeply [ sort grep { !$defined{$_} } keys %used ], [],
  'themeTokens__every_token_read__is_defined';
is_deeply [ sort grep { !$used{$_} } keys %defined ], [],
  'themeTokens__every_token_defined__is_read';

done_testing;
