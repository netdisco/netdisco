#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::CssRules qw/read_text css_rules css_rule_blocks split_selectors has_color_literal is_guarded/;

# These rules redraw Bootstrap's own components in the Bootstrap 2 look. A
# theme written against stock Bootstrap must not get them, so each one's
# colors sit behind the base-layer guard and nowhere else.
my @BASE_LAYER = (
  ':root', '.btn',
  '.btn:not(.btn-primary, .btn-success, .btn-danger, .btn-warning, .btn-info, .btn-light, .btn-dark, .btn-link)',
  '.btn:active', '.btn.active', '.btn-link', '.btn-group > .btn + .dropdown-toggle',
  '.toggle > .toggle-group > .toggle-off',
  '.btn-info', '.btn-primary', '.btn-danger', '.btn-success', '.btn-warning', '.btn-dark',
  '.badge', '.badge.text-bg-info', '.badge.text-bg-warning', '.badge.alert-danger',
  '.form-control', '.form-select', '.input-group-text', '.form-control-plaintext',
  '.navbar', '.navbar .nav-link.active', '.navbar.bg-dark',
  '.dropdown-item:hover', '.dropdown-item:focus',
  '.nav-tabs .nav-link:not(.active):hover', '.nav-tabs .nav-link:not(.active):focus',
  'code', 'pre', '.table', 'table.dataTable.table-bordered',
  'div.dt-container div.nd_datatables-pager div.dt-paging ul.pagination',
  'div.dt-container div.dt-processing',
  '.navbar .dropend > .dropdown-toggle::after',
);

my @decls = css_rules(read_text('share/public/css/netdisco.css'));

# control: the guard test must be able to fail
ok !is_guarded('.btn'), 'isGuarded__bare_selector__is_not_guarded';
ok is_guarded(':where(:root:not([data-bs-theme]), :root[data-nd-base-layer]) .btn, '
            . ':where(:root:not([data-bs-theme]), :root[data-nd-base-layer]) .badge'),
  'isGuarded__every_part_prefixed__is_guarded';
ok !is_guarded(':where(:root:not([data-bs-theme]), :root[data-nd-base-layer]) .btn, .badge'),
  'isGuarded__one_part_bare__is_not_guarded';

foreach my $selector (@BASE_LAYER) {
  my @unguarded = grep {
    !is_guarded($_->{selector})
      and $_->{property} !~ /^--nd-/
      and (grep { $_ eq $selector } Test::Netdisco::CssRules::split_selectors($_->{selector}))
      and has_color_literal($_->{value})
  } @decls;
  is_deeply [ map { "line $_->{line}: $_->{property}" } @unguarded ], [],
    "baseLayer__${selector}__has_no_unguarded_color";

  my $guarded_form = $selector eq ':root'
    ? $Test::Netdisco::CssRules::ROOT_GUARD
    : "$Test::Netdisco::CssRules::GUARD $selector";
  ok scalar(grep { my $rule = $_->{selector};
                   is_guarded($rule)
                   and grep { $_ eq $guarded_form }
                         Test::Netdisco::CssRules::split_selectors($rule) } @decls),
    "baseLayer__${selector}__has_a_guarded_rule";
}

# A guarded shorthand lands after the rule it was split from at equal
# specificity, so it resets any longhand the original rule kept.
# border-radius, border-collapse and border-spacing are not reset by `border`.
my $NOT_RESET = qr/^border-(?:radius|collapse|spacing)/;
my @SHORTHANDS = qw/border background margin padding outline font/;
my @blocks = css_rule_blocks(read_text('share/public/css/netdisco.css'));
my $guard_prefix = qr/^\Q$Test::Netdisco::CssRules::GUARD\E /;

sub unguarded_selector_key {
  my $selector = shift;
  return ':root' if $selector eq $Test::Netdisco::CssRules::ROOT_GUARD;
  return join ', ', map { (my $bare = $_) =~ s/$guard_prefix//; $bare } split_selectors($selector);
}

my @left_behind;
foreach my $index (0 .. $#blocks) {
  my $guarded = $blocks[$index];
  next unless is_guarded($guarded->{selector});
  my $key = unguarded_selector_key($guarded->{selector});
  my ($original) = grep { !is_guarded($_->{selector})
                          and join(', ', split_selectors($_->{selector})) eq $key }
                   reverse @blocks[0 .. $index - 1];
  next unless $original;

  my @properties = map { $_->{property} } @{ $guarded->{decls} };
  foreach my $shorthand (grep { my $name = $_; grep { $_ eq $name } @properties } @SHORTHANDS) {
    my $position = (grep { $properties[$_] eq $shorthand } 0 .. $#properties)[-1];
    my %repeated = map { $_ => 1 } @properties[ $position + 1 .. $#properties ];
    foreach my $longhand (grep { /^\Q$shorthand\E-/ and !$repeated{$_} and !/$NOT_RESET/ }
                          map { $_->{property} } @{ $original->{decls} }) {
      push @left_behind, "line $guarded->{line}: $guarded->{selector} sets $shorthand, "
                       . "line $original->{line} keeps $longhand";
    }
  }
}
is_deeply \@left_behind, [], 'baseLayer__guarded_shorthands__do_not_reset_a_longhand_left_behind';

done_testing;
