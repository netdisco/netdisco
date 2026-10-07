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
  like $page, qr/<html data-nd-theme-default="xtstock" data-nd-theme-root="[^"]*\/theme\/">/,
    'mainLayout__theme_with_a_marker_comment__carries_only_the_theme_default';
};

setting(web_theme => 'classic');
App::Netdisco::Web::Theme::resolve_configured_theme();

test_psgi $app, sub {
  my $cb = shift;
  my $page = $cb->(GET '/login')->content;
  like $page, qr/<html data-nd-theme-default="classic" data-nd-theme-root="[^"]*\/theme\/">/,
    'mainLayout__shipped_classic__carries_only_the_theme_default';
};

setting(web_theme => '');
App::Netdisco::Web::Theme::resolve_configured_theme();
test_psgi $app, sub {
  my $cb = shift;
  my $page = $cb->(GET '/login')->content;
  like $page, qr/<html data-nd-theme-default="" data-nd-theme-root="[^"]*\/theme\/">/,
    'mainLayout__no_theme__carries_an_empty_default';
};

setting(web_theme => 'auto');
App::Netdisco::Web::Theme::resolve_configured_theme();
is +(setting('_web_theme') || {})->{name}, 'auto',
  'resolveConfiguredTheme__auto__keeps_its_name';
like +(setting('_web_theme') || {})->{path}, qr{/themes/dark\.css\z},
  'resolveConfiguredTheme__auto__serves_the_dark_sheet';
test_psgi $app, sub {
  my $cb = shift;
  my $page = $cb->(GET '/login')->content;
  like $page, qr{<script src="[^"]*/javascripts/netdisco-theme\.js\?v=[^"]*"></script>},
    'mainLayout__any_theme__loads_the_resolver';
  unlike $page, qr/<html[^>]*data-bs-theme=/,
    'mainLayout__auto__leaves_the_color_mode_to_the_resolver';
};

done_testing;
