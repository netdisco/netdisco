#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

# A theme sets a color mode and nothing else, so the page carries only its
# data-bs-theme attribute, whatever comments the theme file holds.

my ($envdir, $sitedir);
BEGIN {
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');

  $sitedir = File::Temp->newdir(CLEANUP => 1);
  mkdir catdir("$sitedir", 'themes') or die "cannot make themes dir: $!";
  open my $css, '>', catfile("$sitedir", 'themes', 'xtstock.css')
    or die "cannot write the theme: $!";
  print $css "/* netdisco: base-layer */\n[data-bs-theme=\"xtstock\"] { --bs-primary: #123456; }\n";
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
use App::Netdisco::Web::Theme ();

my $app = eval { Plack::Util::load_psgi(catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg')) };
BAIL_OUT("could not load the web app: $@") unless $app;

sub setting { return Dancer::Config::setting(@_) }

ok !exists +(setting('_web_theme') || {})->{base_layer},
  'resolveConfiguredTheme__theme_with_a_marker_comment__records_no_base_layer';

test_psgi $app, sub {
  my $cb = shift;
  my $page = $cb->(GET '/login')->content;
  like $page, qr/<html data-bs-theme="xtstock">/,
    'mainLayout__theme_with_a_marker_comment__carries_only_the_color_mode_attribute';
};

setting(web_theme => 'classic');
App::Netdisco::Web::Theme::resolve_configured_theme();

test_psgi $app, sub {
  my $cb = shift;
  my $page = $cb->(GET '/login')->content;
  like $page, qr/<html data-bs-theme="classic">/,
    'mainLayout__shipped_classic__carries_only_the_color_mode_attribute';
};

setting(web_theme => '');
App::Netdisco::Web::Theme::resolve_configured_theme();
test_psgi $app, sub {
  my $cb = shift;
  my $page = $cb->(GET '/login')->content;
  like $page, qr/<html>/, 'mainLayout__no_theme__carries_no_attribute';
};

done_testing;
