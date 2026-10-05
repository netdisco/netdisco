#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::CssRules qw/read_text css_rules/;

# A shipped theme that sets a token netdisco.css no longer defines silently
# stops applying, the same failure xt/117 guards for Bootstrap's variables.
my %defined = map { $_->{property} => 1 }
  grep { $_->{selector} eq ':root' and $_->{property} =~ /^--nd-/ }
  css_rules(read_text('share/public/css/netdisco.css'));

ok scalar(keys %defined), 'shippedThemes__token_block__was_found';

my @themes = glob 'share/public/css/themes/*.css';
ok( (grep { m{/dark\.css$} } @themes), 'shippedThemes__dark__is_shipped' );

foreach my $theme (@themes) {
  my %set = map { $_->{property} => 1 } grep { $_->{property} =~ /^--nd-/ }
    css_rules(read_text($theme));
  is_deeply [ sort grep { !$defined{$_} } keys %set ], [],
    "shippedTheme__${theme}__sets_only_tokens_netdisco_defines";
}

done_testing;
