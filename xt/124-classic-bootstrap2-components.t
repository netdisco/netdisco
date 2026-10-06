#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::CssRules qw/read_text css_rules css_rule_blocks split_selectors has_color_literal is_classic_scoped/;

# Bootstrap's own components draw in stock Bootstrap colors unless the theme
# is classic, which draws them in the Bootstrap 2 look.
my @BOOTSTRAP2 = (
  ':root', '.btn',
  '.btn:not(.btn-primary, .btn-success, .btn-danger, .btn-warning, .btn-info, .btn-light, .btn-dark, .btn-link)',
  '.btn:active', '.btn.active', '.btn-link', '.btn-group > .btn + .dropdown-toggle',
  '.toggle > .toggle-group > .toggle-off',
  '.btn-info', '.btn-primary', '.btn-danger', '.btn-success', '.btn-warning', '.btn-dark',
  '.badge', '.badge.text-bg-info', '.badge.text-bg-warning', '.badge.alert-danger',
  '.form-control', '.form-select', '.input-group-text', '.form-control-plaintext',
  '.navbar', '.navbar .nav-link.active', '.navbar.bg-dark',
  '.nav-tabs .nav-link:not(.active):hover', '.nav-tabs .nav-link:not(.active):focus',
  'code', 'pre', '.table',
  'div.dt-container div.nd_datatables-pager div.dt-paging ul.pagination',
  'div.dt-container div.dt-processing',
  '.navbar .dropend > .dropdown-toggle::after',
);
# Classic draws these through its own variables.
my %CLASSIC_OWN = (
  '.badge.text-bg-dark'  => [ '[data-bs-theme="classic"]', '--bs-dark-rgb' ],
  '.dropdown-item:hover' => [ '[data-bs-theme="classic"] .dropdown-menu', '--bs-dropdown-link-hover-bg', '--bs-dropdown-link-hover-color' ],
  '.dropdown-item:focus' => [ '[data-bs-theme="classic"] .dropdown-menu', '--bs-dropdown-link-hover-bg', '--bs-dropdown-link-hover-color' ],
);

my $netdisco = read_text('share/public/css/netdisco.css');
my $classic  = read_text('share/public/css/themes/classic.css');
my @nd_decls      = css_rules($netdisco);
my @classic_decls = css_rules($classic);

# control: the scope test must be able to fail
ok is_classic_scoped(':where([data-bs-theme="classic"]) .btn'), 'isClassicScoped__scoped_selector__is_scoped';
ok is_classic_scoped('[data-bs-theme="classic"]'), 'isClassicScoped__theme_root__is_scoped';
ok !is_classic_scoped('.btn'), 'isClassicScoped__bare_selector__is_not_scoped';
ok !is_classic_scoped(':where([data-bs-theme="classic"]) .btn, .badge'),
  'isClassicScoped__one_part_bare__is_not_scoped';

unlike $netdisco, qr/data-nd-base-layer/, 'defaultPalette__netdisco_css__has_no_base_layer_guard';

foreach my $selector (@BOOTSTRAP2, sort keys %CLASSIC_OWN) {
  my @colored = grep {
    $_->{property} !~ /^--nd-/
      and has_color_literal($_->{value})
      and grep { $_ eq $selector } split_selectors($_->{selector})
  } @nd_decls;
  is_deeply [ map { "line $_->{line}: $_->{property}" } @colored ], [],
    "defaultPalette__${selector}__is_stock_bootstrap";
}

foreach my $selector (@BOOTSTRAP2) {
  my $scoped = $selector eq ':root'
    ? $Test::Netdisco::CssRules::CLASSIC_ROOT
    : "$Test::Netdisco::CssRules::CLASSIC_SCOPE $selector";
  ok scalar(grep { has_color_literal($_->{value})
                   and grep { $_ eq $scoped } split_selectors($_->{selector}) } @classic_decls),
    "classicTheme__${selector}__keeps_the_bootstrap2_color";
}

foreach my $selector (sort keys %CLASSIC_OWN) {
  my ($rule, @properties) = @{ $CLASSIC_OWN{$selector} };
  foreach my $property (@properties) {
    ok scalar(grep { $_->{property} eq $property
                     and grep { $_ eq $rule } split_selectors($_->{selector}) } @classic_decls),
      "classicTheme__${selector}__draws_through_its_own_${property}";
  }
}

# Each of these undoes a rule above it at the same weight, so it must come
# after that rule, in this file, and netdisco.css must not set it.
my $CLASSIC_SCOPE = $Test::Netdisco::CssRules::CLASSIC_SCOPE;
my $PLAIN = '.btn:not(.btn-primary, .btn-success, .btn-danger, .btn-warning, .btn-info, .btn-light, .btn-dark, .btn-link)';
my @UNDO = (
  [ $PLAIN,        'background-image', '.btn:active' ],
  [ $PLAIN,        'background-image', '.btn:disabled' ],
  [ '.btn',        'box-shadow',       '.btn-link' ],
  [ '.btn:active', 'box-shadow',       '.btn:disabled' ],
);
my @classic_blocks = css_rule_blocks($classic);
sub position_of {
  my ($selector, $test) = @_;
  my ($at) = grep {
    (grep { $_ eq "$CLASSIC_SCOPE $selector" } split_selectors($classic_blocks[$_]{selector}))
      and grep { $test->($_) } @{ $classic_blocks[$_]{decls} }
  } 0 .. $#classic_blocks;
  return $at;
}
foreach my $undo (@UNDO) {
  my ($rule, $property, $undoer) = @$undo;
  my $rule_at = position_of($rule, sub { $_[0]{property} eq $property and $_[0]{value} ne 'none' });
  my $undo_at = position_of($undoer, sub { $_[0]{property} eq $property and $_[0]{value} eq 'none' });
  ok defined($rule_at) && defined($undo_at) && $undo_at > $rule_at,
    "classicTheme__${undoer}_${property}__comes_after_the_rule_it_undoes";
  my @in_default = grep { $_->{property} eq $property
                          and grep { $_ eq $undoer } split_selectors($_->{selector}) } @nd_decls;
  is scalar(@in_default), 0, "defaultPalette__${undoer}_${property}__is_left_to_classic";
}

# classic.css loads after netdisco.css, so a shorthand here resets any longhand
# netdisco.css sets on the same selector. `border` does not reset
# border-radius, border-collapse or border-spacing.
my $NOT_RESET = qr/^border-(?:radius|collapse|spacing)/;
my @SHORTHANDS = qw/border background margin padding outline font/;
my @nd_blocks = css_rule_blocks($netdisco);
my @scoped = grep { is_classic_scoped($_->{selector}) } css_rule_blocks($classic);

sub bare_key {
  my $selector = shift;
  return join ', ', map {
    my $part = $_;
    $part eq $Test::Netdisco::CssRules::CLASSIC_ROOT ? ':root'
      : do { (my $bare = $part) =~ s/^\Q$Test::Netdisco::CssRules::CLASSIC_SCOPE\E //; $bare }
  } split_selectors($selector);
}

sub original_of {
  my $key = bare_key(shift);
  my ($original) = grep { join(', ', split_selectors($_->{selector})) eq $key } reverse @nd_blocks;
  return $original;
}

my @left_behind;
foreach my $block (@scoped) {
  my $original = original_of($block->{selector}) or next;
  my @properties = map { $_->{property} } @{ $block->{decls} };
  foreach my $shorthand (grep { my $name = $_; grep { $_ eq $name } @properties } @SHORTHANDS) {
    my $position = (grep { $properties[$_] eq $shorthand } 0 .. $#properties)[-1];
    my %repeated = map { $_ => 1 } @properties[ $position + 1 .. $#properties ];
    foreach my $longhand (grep { /^\Q$shorthand\E-/ and !$repeated{$_} and !/$NOT_RESET/ }
                          map { $_->{property} } @{ $original->{decls} }) {
      push @left_behind, "line $block->{line}: $block->{selector} sets $shorthand, "
                       . "netdisco.css line $original->{line} keeps $longhand";
    }
  }
}
is_deeply \@left_behind, [], 'classicTheme__component_shorthands__do_not_reset_a_netdisco_longhand';

# A border shorthand here may replace a whole border but not part of one, so
# it is flagged when netdisco.css keeps some of that box's border structure.
my %STRUCTURE = (
  border  => qr/^border-(?:collapse|spacing|width|style|(?:top|right|bottom|left)(?:-width|-style)?)$/,
  outline => qr/^outline-(?:width|style)$/,
);
my $WIDTH_OR_STYLE = qr/\b(?:\d+(?:\.\d+)?(?:px|em|rem)|thin|medium|thick|none|hidden|solid|dashed|dotted|double|groove|ridge|inset|outset)\b/;
my @carries_structure_missing;
foreach my $block (@scoped) {
  my $original = original_of($block->{selector}) or next;
  my %original_properties = map { $_->{property} => 1 } @{ $original->{decls} };
  foreach my $declaration (grep { $_->{property} =~ /^(?:border|outline)$/
                                  and $_->{value} =~ $WIDTH_OR_STYLE } @{ $block->{decls} }) {
    my $name = $declaration->{property};
    my @kept = grep { /$STRUCTURE{$name}/ } keys %original_properties;
    next unless @kept;
    push @carries_structure_missing,
      "line $block->{line}: $block->{selector} sets $name '$declaration->{value}', "
      . "netdisco.css line $original->{line} keeps " . join(', ', sort @kept);
  }
}
is_deeply \@carries_structure_missing, [],
  'classicTheme__component_shorthands__do_not_half_replace_a_border';

done_testing;
