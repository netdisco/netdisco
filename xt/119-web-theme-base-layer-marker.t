#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

# A theme written for netdisco opts in to netdisco's look for Bootstrap's own
# components; one written against stock Bootstrap must not get it.
my ($envdir, $sitedir);
BEGIN {
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');

  $sitedir = File::Temp->newdir(CLEANUP => 1);
  mkdir catdir("$sitedir", 'themes') or die "cannot make themes dir: $!";
  open my $css, '>', catfile("$sitedir", 'themes', 'xtstock.css')
    or die "cannot write the theme: $!";
  print $css "[data-bs-theme=\"xtstock\"] { --bs-primary: #123456; }\n";
  close $css;

  $envdir = File::Temp->newdir(CLEANUP => 1);
  open my $env, '>', catfile("$envdir", 'testing.yml')
    or die "cannot write the test environment file: $!";
  print $env "web_theme: 'xtstock'\ntemplate_paths: ['$sitedir']\n";
  close $env;

  $ENV{DANCER_ENVDIR} = "$envdir";
  $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;
use App::Netdisco::Web::Theme 'theme_uses_base_layer';

is theme_uses_base_layer("/* netdisco: base-layer */\n[data-bs-theme=\"x\"] {}"), 1,
  'themeUsesBaseLayer__marker_comment__opts_in';
is theme_uses_base_layer("/*netdisco:base-layer*/"), 1,
  'themeUsesBaseLayer__marker_without_spaces__opts_in';
is theme_uses_base_layer("/*   netdisco:   base-layer   */"), 1,
  'themeUsesBaseLayer__marker_with_extra_spaces__opts_in';
is theme_uses_base_layer("[data-bs-theme=\"x\"] { --bs-primary: #000; }"), 0,
  'themeUsesBaseLayer__no_marker__stays_out';
is theme_uses_base_layer("/* netdisco: base-layers */"), 0,
  'themeUsesBaseLayer__a_longer_word__is_not_the_marker';
is theme_uses_base_layer("netdisco: base-layer"), 0,
  'themeUsesBaseLayer__the_words_outside_a_comment__are_not_the_marker';

my $app = eval { Plack::Util::load_psgi(catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg')) };
BAIL_OUT("could not load the web app: $@") unless $app;

sub setting { return Dancer::Config::setting(@_) }

is +(setting('_web_theme') || {})->{base_layer}, 0,
  'resolveConfiguredTheme__theme_without_marker__records_no_base_layer';

test_psgi $app, sub {
  my $cb = shift;
  my $page = $cb->(GET '/login')->content;
  like $page, qr/<html data-bs-theme="xtstock">/,
    'mainLayout__theme_without_marker__carries_only_the_color_mode_attribute';
};

setting(web_theme => 'classic');
App::Netdisco::Web::Theme::resolve_configured_theme();
is +(setting('_web_theme') || {})->{base_layer}, 1,
  'resolveConfiguredTheme__shipped_classic__opts_in';

test_psgi $app, sub {
  my $cb = shift;
  my $page = $cb->(GET '/login')->content;
  like $page, qr/<html data-bs-theme="classic" data-nd-base-layer>/,
    'mainLayout__theme_with_marker__carries_the_base_layer_attribute';
};

setting(web_theme => '');
App::Netdisco::Web::Theme::resolve_configured_theme();
test_psgi $app, sub {
  my $cb = shift;
  my $page = $cb->(GET '/login')->content;
  like $page, qr/<html>/, 'mainLayout__no_theme__carries_no_attribute';
};

done_testing;
