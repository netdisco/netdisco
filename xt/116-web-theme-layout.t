#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template stash_for/;

sub render_main {
  my $theme = shift;
  my $stash = stash_for('layouts/main.tt');
  $stash->{settings}->{_web_theme} = $theme;
  my ($html, $error) = render_template('layouts/main.tt', $stash);
  die "layouts/main.tt failed to render: $error" if $error;
  return $html;
}

my $plain = render_main(undef);
like $plain, qr/<html data-nd-theme-default="" /, 'mainLayout__no_theme__carries_an_empty_default';
unlike $plain, qr/<html[^>]*data-bs-theme=/, 'mainLayout__no_theme__sets_no_color_mode_attribute';
unlike $plain, qr/theme\.css/, 'mainLayout__no_theme__links_no_theme_stylesheet';

my $themed = render_main({ name => 'classic', path => '/x', mtime => 1700000000 });
like $themed, qr/<html data-nd-theme-default="classic" /,
  'mainLayout__theme__carries_the_theme_default_for_the_resolver';
like $themed, qr{/theme\.css\?v=1700000000"},
  'mainLayout__theme__links_the_stylesheet_keyed_on_its_mtime';
like $themed, qr{netdisco\.css.*/theme\.css}s,
  'mainLayout__theme__loads_after_netdisco_css_so_its_rules_win';

my $odd = render_main({ name => 'a"b', path => '/x', mtime => 1 });
like $odd, qr/data-nd-theme-default="a&quot;b"/, 'mainLayout__theme_name__is_escaped_in_the_attribute';

# The user menu's theme switch is icon-only so there is nothing to translate,
# but each button still needs words for hover text and screen readers.
my $auto = render_main({ name => 'auto', path => '/x', mtime => 1 });
my @choices = $auto =~ m/data-nd-theme-choice="([^"]+)"/g;
is_deeply \@choices, [qw/light auto dark/], 'mainLayout__auto__offers_light_computer_dark_in_order';
foreach my $label ('Light', 'Same as computer', 'Dark') {
  like $auto, qr/<button[^>]*data-nd-theme-choice="[^"]+"[^>]*title="\Q$label\E" aria-label="\Q$label\E"/,
    'mainLayout__auto__labels_the_' . (lc($label) =~ s/ /_/gr) . '_button';
}
like $auto, qr/data-nd-theme-choice.*Log Out/s, 'mainLayout__auto__puts_the_switch_above_log_out';

unlike $themed, qr/data-nd-theme-choice/, 'mainLayout__configured_theme__has_no_switch';
unlike $plain, qr/data-nd-theme-choice/, 'mainLayout__no_theme__has_no_switch';

done_testing;
