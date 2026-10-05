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
like $plain, qr/<html>/, 'mainLayout__no_theme__leaves_the_html_element_bare';
unlike $plain, qr/theme\.css/, 'mainLayout__no_theme__links_no_theme_stylesheet';

my $themed = render_main({ name => 'classic', path => '/x', mtime => 1700000000 });
like $themed, qr/<html data-bs-theme="classic">/,
  'mainLayout__theme__sets_the_bootstrap_color_mode_attribute';
like $themed, qr{/theme\.css\?v=1700000000"},
  'mainLayout__theme__links_the_stylesheet_keyed_on_its_mtime';
like $themed, qr{netdisco\.css.*/theme\.css}s,
  'mainLayout__theme__loads_after_netdisco_css_so_its_rules_win';

my $odd = render_main({ name => 'a"b', path => '/x', mtime => 1 });
like $odd, qr/data-bs-theme="a&quot;b"/, 'mainLayout__theme_name__is_escaped_in_the_attribute';

done_testing;
