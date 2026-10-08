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
  [ '.nd_hero-row .bg-body-tertiary', 'background-color', 'var(--nd-hero-bg) !important' ],
) {
  my ($selector, $property, $value) = @$case;
  ok( (grep { $_->{property} eq $property and $_->{value} eq $value
                and grep { $_ eq $selector } split /\s*,\s*/, $_->{selector} } @nd),
    "netdiscoCss__${selector}_${property}__reads_its_token" );
}

# Bootstrap's link blue and its info and warning icon colors miss WCAG
# contrast on netdisco's tinted backgrounds, so stock light uses darker steps
# from Bootstrap's own palette. A theme attribute switches this off.
my $LIGHT = ':root:not([data-bs-theme])';
foreach my $case (
  [ $LIGHT, '--bs-link-color', 'var(--nd-light-link)' ],
  [ $LIGHT, '--bs-link-color-rgb', 'var(--nd-light-link-rgb)' ],
  [ $LIGHT, '--bs-link-hover-color', 'var(--nd-light-link-hover)' ],
  [ $LIGHT, '--bs-link-hover-color-rgb', 'var(--nd-light-link-hover-rgb)' ],
  [ "$LIGHT i.text-info", 'color', 'var(--nd-light-info-icon) !important' ],
  [ "$LIGHT i.text-warning", 'color', 'var(--nd-light-warning-icon) !important' ],
) {
  my ($selector, $property, $value) = @$case;
  ok( (grep { $_->{property} eq $property and $_->{value} eq $value
                and grep { $_ eq $selector } split /\s*,\s*/, $_->{selector} } @nd),
    "netdiscoCss__light_${property}_on_${selector}__uses_the_darker_step" );
}

# Bootstrap 5's bare .btn is transparent and borderless, its info badge is
# heavy, and its current page is the loudest blue on the page. Stock light and
# dark soften all three; classic and site themes keep their own. The prefix
# holds a comma, so these compare the whole selector rather than splitting.
my $QUIET = ':is(:root:not([data-bs-theme]), [data-bs-theme="dark"])';
my $PLAIN_BTN = '.btn:not(.btn-primary, .btn-success, .btn-danger, .btn-warning, '
  . '.btn-info, .btn-light, .btn-dark, .btn-link, .btn-secondary)';
sub quiet_has {
  my ($selector, %expected) = @_;
  my @rules = grep { $_->{selector} eq "$QUIET $selector" } @nd;
  foreach my $property (keys %expected) {
    return 0 unless grep { $_->{property} eq $property
                           and $_->{value} eq $expected{$property} } @rules;
  }
  return 1;
}

ok( quiet_has($PLAIN_BTN,
    '--bs-btn-color' => 'var(--bs-body-color)',
    '--bs-btn-bg' => 'var(--bs-tertiary-bg)',
    '--bs-btn-border-color' => 'var(--bs-border-color)',
    '--bs-btn-hover-color' => 'var(--bs-emphasis-color)',
    '--bs-btn-hover-bg' => 'var(--nd-secondary-bg)',
    '--bs-btn-hover-border-color' => 'var(--bs-border-color)',
    '--bs-btn-active-color' => 'var(--bs-emphasis-color)',
    '--bs-btn-active-bg' => 'var(--nd-secondary-bg)',
    '--bs-btn-active-border-color' => 'var(--bs-border-color)' ),
  'netdiscoCss__plain_button__draws_a_quiet_box_in_light_and_dark' );

ok( quiet_has('.badge.text-bg-info',
    'color' => 'var(--bs-info-text-emphasis) !important',
    'background-color' => 'var(--bs-info-bg-subtle) !important',
    'border' => 'var(--bs-border-width) solid var(--bs-info-border-subtle)' ),
  'netdiscoCss__info_badge__uses_the_subtle_style_in_light_and_dark' );

ok( quiet_has('.badge', '--bs-badge-font-weight' => '600'),
  'netdiscoCss__badge__weighs_600_in_light_and_dark' );

ok( quiet_has('.pagination',
    '--bs-pagination-active-color' => 'var(--bs-primary-text-emphasis)',
    '--bs-pagination-active-bg' => 'var(--bs-primary-bg-subtle)',
    '--bs-pagination-active-border-color' => 'var(--bs-primary-border-subtle)' ),
  'netdiscoCss__current_page__uses_primary_subtle_in_light_and_dark' );

my @fa_border_rules = grep { $_->{selector} eq "$QUIET .btn .fa-border" } @nd;
my $has_width = scalar grep { $_->{property} eq '--fa-border-width' and $_->{value} eq '0' } @fa_border_rules;
my $has_padding = scalar grep { $_->{property} eq '--fa-border-padding' } @fa_border_rules;
ok( ($has_width and !$has_padding),
  'netdiscoCss__icon_border_in_a_button__is_dropped_in_light_and_dark' );

ok( quiet_has('.badge .nd_delete-me', 'color' => 'inherit'),
  'netdiscoCss__badge_delete_icon__takes_the_badge_color_in_light_and_dark' );

ok( (grep { $_->{selector} eq '[data-bs-theme="dark"] .badge.text-bg-dark'
              and $_->{property} eq 'background-color'
              and $_->{value} eq 'var(--nd-secondary-bg) !important' } @dark),
  'darkTheme__dark_badge__uses_the_secondary_background_token' );

ok( quiet_has('.btn-info',
    '--bs-btn-color' => 'var(--bs-info-text-emphasis)',
    '--bs-btn-bg' => 'var(--bs-info-bg-subtle)',
    '--bs-btn-border-color' => 'var(--bs-info-border-subtle)',
    '--bs-btn-hover-color' => 'var(--bs-emphasis-color)',
    '--bs-btn-hover-bg' => 'var(--bs-info-border-subtle)',
    '--bs-btn-hover-border-color' => 'var(--bs-info-border-subtle)',
    '--bs-btn-active-color' => 'var(--bs-emphasis-color)',
    '--bs-btn-active-bg' => 'var(--bs-info-border-subtle)',
    '--bs-btn-active-border-color' => 'var(--bs-info-border-subtle)',
    '--bs-btn-disabled-color' => 'var(--bs-info-text-emphasis)',
    '--bs-btn-disabled-bg' => 'var(--bs-info-bg-subtle)',
    '--bs-btn-disabled-border-color' => 'var(--bs-info-border-subtle)' ),
  'netdiscoCss__info_button__uses_the_subtle_style_in_light_and_dark' );

# Bootstrap's field borders are 1.3:1 against the page in light and dark,
# under WCAG 1.4.11's 3:1. One class of specificity, so Bootstrap's focus,
# checked and validation borders still win.
my $FIELDS = ':where(:root:not([data-bs-theme]), [data-bs-theme="dark"]) '
  . ':is(.form-control, .form-select, .form-check-input, .input-group-text)';
ok( (grep { $_->{selector} eq $FIELDS
              and $_->{property} eq 'border-color'
              and $_->{value} eq 'var(--nd-control-border)' } @nd),
  'netdiscoCss__field_border__reads_the_control_border_token_in_light_and_dark' );

my %root_token = map { $_->{property} => $_->{value} }
  grep { $_->{selector} eq ':root' and $_->{property} =~ /^--nd-/ } @nd;
is $root_token{'--nd-control-border'}, 'var(--bs-gray-600)',
  'netdiscoCss__control_border_token__is_bootstrap_gray_600';
is $root_token{'--nd-radio-border'}, 'var(--nd-control-border)',
  'netdiscoCss__netmap_radio_border__follows_the_control_border';

# Dark panels (sidebar, login box) are lighter than the page, where gray-600
# falls to 2.45:1; gray-500 is the darkest palette step over 3:1 on all of them.
ok( (grep { $_->{selector} eq '[data-bs-theme="dark"]'
              and $_->{property} eq '--nd-control-border'
              and $_->{value} eq 'var(--bs-gray-500)' } @dark),
  'darkTheme__control_border_token__is_bootstrap_gray_500' );

# The sidebar checkbox boxes sit beside a borderless caption in light and dark,
# so Bootstrap's squared joining edge reads as clipped. Classic borders the
# caption and keeps the join.
my $CHECKBOX_BOX = ':where(:root:not([data-bs-theme]), [data-bs-theme="dark"]) '
  . '.input-group > .input-group-text:has(+ .nd_checkboxlabel)';
ok( (grep { $_->{selector} eq $CHECKBOX_BOX
              and $_->{property} eq 'border-radius'
              and $_->{value} eq 'var(--bs-border-radius) !important' } @nd),
  'netdiscoCss__sidebar_checkbox_box__rounds_all_four_corners_in_light_and_dark' );

# navbar_disco.png is opaque with its own background, so a theme that paints
# the bar another color shows the artwork as a rectangle.
ok( (grep { $_->{selector} eq '.navbar.bg-dark'
              and $_->{property} eq 'background-color'
              and $_->{value} eq 'var(--nd-navbar-bg) !important' } @nd),
  'netdiscoCss__navbar__matches_the_artwork_background_in_every_theme' );

ok( !(grep { $_->{selector} =~ /\.navbar\.bg-dark/ } @dark),
  'darkTheme__navbar__takes_the_shared_color' );

# Bootstrap's colored rows darken on stripe, hover and selection, where the
# light link blue drops under 4.5:1. Dark mixes a smaller share of the strong
# tone so the dark link keeps its margin on every state.
my $ROW_VARIANTS = ':is(.table-success, .table-danger, .table-info)';
foreach my $case (
  [ '--bs-link-color', 'var(--nd-light-row-link)' ],
  [ '--bs-link-color-rgb', 'var(--nd-light-row-link-rgb)' ],
  [ '--bs-link-hover-color', 'var(--nd-light-row-link-hover)' ],
  [ '--bs-link-hover-color-rgb', 'var(--nd-light-row-link-hover-rgb)' ],
) {
  my ($property, $value) = @$case;
  ok( (grep { $_->{selector} eq "$LIGHT $ROW_VARIANTS"
                and $_->{property} eq $property and $_->{value} eq $value } @nd),
    "netdiscoCss__colored_row_links_${property}__use_the_darker_step_in_light" );
}

foreach my $variant (qw/success danger/, 'info') {
  my $mix = "color-mix(in srgb, var(--bs-$variant-bg-subtle), "
    . "var(--bs-$variant-border-subtle) 30%)";
  foreach my $property (qw/--bs-table-hover-bg --bs-table-active-bg/) {
    ok( (grep { $_->{selector} eq qq{[data-bs-theme="dark"] .table-$variant}
                  and $_->{property} eq $property and $_->{value} eq $mix } @dark),
      "darkTheme__colored_row_${variant}_${property}__mixes_30_percent_of_the_strong_tone" );
  }
}

done_testing;
