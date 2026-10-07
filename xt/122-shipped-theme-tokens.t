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

# Bootstrap keeps .text-success and .text-danger at their light values in dark
# mode, under 3:1 on striped dark rows. Text keeps Bootstrap's color; only
# icons are lifted.
my @dark = css_rules(read_text('share/public/css/themes/dark.css'));
foreach my $variant (qw/success danger/) {
  my $selector = qq{[data-bs-theme="dark"] i.text-$variant};
  ok( (grep { $_->{property} eq 'color'
                and $_->{value} eq "var(--bs-$variant-text-emphasis) !important"
                and grep { $_ eq $selector } split /\s*,\s*/, $_->{selector} } @dark),
    "darkTheme__text_${variant}_icon__uses_bootstrap_dark_emphasis_color" );
}

# Bootstrap's base red, the light value, measures under 3:1 on the dark sidebar.
ok( (grep { $_->{selector} eq '[data-bs-theme="dark"]'
              and $_->{property} eq '--nd-pin-active'
              and $_->{value} eq 'var(--bs-danger-text-emphasis)' } @dark),
  'darkTheme__pinned_sidebar_thumbtack__uses_bootstrap_dark_danger_emphasis' );

# A report's inline <style> is a color no theme reaches and a strict CSP
# blocks, so the group rows read a token from netdisco.css instead.
my @inline_style = grep {
  open my $fh, '<', $_ or die "cannot read $_: $!";
  local $/; my $src = <$fh>; $src =~ /<style/;
} glob 'share/views/ajax/{report,search}/*.tt';
is_deeply \@inline_style, [], 'reportTemplates__group_rows__carry_no_inline_style';

my @nd = css_rules(read_text('share/public/css/netdisco.css'));
foreach my $case (
  [ '.radio label::before', 'border-color', 'var(--nd-radio-border)' ],
  [ '.radio label::before', 'background-color', 'var(--nd-radio-bg)' ],
  [ '.radio label::after', 'background-color', 'var(--nd-radio-dot)' ],
  [ 'tr.group', 'background-color', 'var(--nd-group-row-bg) !important' ],
) {
  my ($selector, $property, $value) = @$case;
  ok( (grep { $_->{property} eq $property and $_->{value} eq $value
                and grep { $_ eq $selector } split /\s*,\s*/, $_->{selector} } @nd),
    "netdiscoCss__${selector}_${property}__reads_its_token" );
}

done_testing;
