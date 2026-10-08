#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::CssRules qw/read_text css_rules has_color_literal/;

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
        and !($_->{selector} eq ':root' and $_->{property} =~ /^--nd-/)
    } css_rules($css);
}

is_deeply [ stray_colors('control', '.nd_x { color: #123456; }') ],
  [ 'control line 1: .nd_x { color }' ],
  'strayColors__control_with_a_literal__is_reported';
is_deeply [ stray_colors('control', '.nd_x { color: floralWhite; }') ],
  [ 'control line 1: .nd_x { color }' ],
  'strayColors__control_with_a_named_color__is_reported';
is_deeply [ stray_colors('control', '.nd_x { --bs-success-rgb: 70, 136, 71; }') ],
  [ 'control line 1: .nd_x { --bs-success-rgb }' ],
  'strayColors__control_with_a_number_triple__is_reported';
is_deeply [ stray_colors('control', '.nd_x { white-space: nowrap; }') ], [],
  'strayColors__control_with_white_space__is_clean';
is_deeply [ stray_colors('control', ':root { --nd-x: #123456; } .nd_x { color: var(--nd-x); }') ], [],
  'strayColors__control_reading_a_token__is_clean';

foreach my $name (sort keys %SHEETS) {
  is_deeply [ stray_colors($name, $SHEETS{$name}) ], [],
    "themeTokens__${name}__has_no_color_outside_tokens";
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

# A token on :root resolves var() at :root, where only Bootstrap's global
# variables exist; a component variable there resolves to nothing.
my $bootstrap = read_text('share/public/css/bootstrap.min.css');
my %global;
foreach my $block ($bootstrap =~ m/(?:^|[\}\/])(?::root,\[data-bs-theme=light\]|\[data-bs-theme=dark\])\{([^}]*)\}/g) {
  $global{$_} = 1 for ($block =~ m/(--bs-[\w-]+):/g);
}
my @root_tokens = grep { $_->{selector} eq ':root' and $_->{property} =~ /^--nd-/ }
  css_rules($SHEETS{'netdisco.css'});
# A token may also read another token defined in the same block, which
# resolves at :root in turn.
sub unknown_variables {
  my ($global, @tokens) = @_;
  my %known = (%$global, map { $_->{property} => 1 } grep { $_->{property} =~ /^--nd-/ } @tokens);
  return map { "$_->{property}: $_->{value}" }
    grep { my $v = $_->{value}; grep { !$known{$_} } ($v =~ m/var\((--[\w-]+)\s*[,)]/g) } @tokens;
}

# A var() fallback is a color no theme can reach, so it stays in view while
# the reference itself is replaced by V, innermost group first. A color
# function wrapped around a reference (rgba(var(--x-rgb), .5)) is the
# reference's color, not a literal, and so is a color-mix() of a reference
# with transparent.
sub literal_outside_var {
  my ($value) = @_;
  1 while $value =~ s/var\(\s*--[\w-]+\s*\)/V/
    or $value =~ s/var\(\s*--[\w-]+\s*,\s*([^()]*)\)/V $1/
    or $value =~ s/(?:rgba?|hsla?|color-mix)\(([^()]*\bV\b[^()]*)\)/$1/;
  return has_color_literal($value);
}

is_deeply [ unknown_variables({}, { property => '--nd-x', value => 'var(--bs-navbar-color, #fff)' }) ],
  [ '--nd-x: var(--bs-navbar-color, #fff)' ],
  'unknownVariables__control_with_a_fallback__is_reported';
is_deeply [ unknown_variables({ '--bs-body-color' => 1 }, { property => '--nd-x', value => 'var(--bs-body-color)' }) ], [],
  'unknownVariables__control_with_a_known_variable__is_clean';
is_deeply [ unknown_variables({ '--bs-body-bg' => 1 },
    { property => '--nd-y', value => 'var(--bs-body-bg)' },
    { property => '--nd-x', value => 'var(--nd-y)' }) ], [],
  'unknownVariables__control_reading_a_defined_token__is_clean';
is_deeply [ unknown_variables({ '--bs-body-bg' => 1 },
    { property => '--nd-y', value => 'var(--bs-body-bg)' },
    { property => '--nd-x', value => 'var(--nd-z)' }) ],
  [ '--nd-x: var(--nd-z)' ],
  'unknownVariables__control_reading_an_undefined_token__is_reported';
ok literal_outside_var('var(--bs-x, #fff)'),
  'literalOutsideVar__control_with_a_fallback__counts_as_a_literal';
ok !literal_outside_var('var(--bs-x)'),
  'literalOutsideVar__control_without_a_fallback__is_clean';
ok literal_outside_var('var(--bs-x, var(--bs-y, #fff))'),
  'literalOutsideVar__control_with_a_nested_fallback__counts_as_a_literal';

ok !literal_outside_var('rgba(var(--bs-white-rgb), 0.55)'),
  'literalOutsideVar__control_with_a_wrapped_reference__is_clean';
ok !literal_outside_var('color-mix(in srgb, var(--bs-white) 55%, transparent)'),
  'literalOutsideVar__control_with_a_reference_mixed_with_transparent__is_clean';
ok literal_outside_var('color-mix(in srgb, #ffffff 55%, transparent)'),
  'literalOutsideVar__control_with_a_literal_mixed_with_transparent__counts_as_a_literal';

is_deeply [ unknown_variables(\%global, @root_tokens) ], [],
  'themeTokens__root_token__reads_only_global_bootstrap_variables_or_root_tokens';

my @literal = grep { literal_outside_var($_->{value}) } @root_tokens;
is_deeply [ sort map { $_->{property} } @literal ],
  [ sort qw/--nd-archived --nd-arrow-down --nd-arrow-up --nd-netmap-running --nd-single-tab --nd-toast-info
    --nd-light-link --nd-light-link-rgb --nd-light-link-hover --nd-light-link-hover-rgb --nd-light-info-icon --nd-light-warning-icon
    --nd-light-row-link --nd-light-row-link-rgb --nd-light-row-link-hover --nd-light-row-link-hover-rgb --nd-navbar-bg/ ],
  'themeTokens__default_palette__uses_literals_only_where_bootstrap_has_no_variable';

done_testing;
