#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

# Resolution happens once at startup, so the theme has to come from an
# environment file layered over config.yml before the app is built, as in xt/94.
my ($envdir, $sitedir);
BEGIN {
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');

  $sitedir = File::Temp->newdir(CLEANUP => 1);
  mkdir catdir("$sitedir", 'themes') or die "cannot make themes dir: $!";
  open my $css, '>', catfile("$sitedir", 'themes', 'xtsite.css')
    or die "cannot write the theme: $!";
  print $css "[data-bs-theme=\"xtsite\"] { --bs-primary: #123456; }\n";
  close $css;

  $envdir = File::Temp->newdir(CLEANUP => 1);
  open my $env, '>', catfile("$envdir", 'testing.yml')
    or die "cannot write the test environment file: $!";
  print $env "web_theme: 'xtsite'\ntemplate_paths: ['$sitedir']\n";
  close $env;

  $ENV{DANCER_ENVDIR} = "$envdir";
  $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;

my $psgi = catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg');
my $app  = eval { Plack::Util::load_psgi($psgi) };
BAIL_OUT("could not load $psgi: $@") unless $app;

sub setting { return Dancer::Config::setting(@_) }

is +(setting('_web_theme') || {})->{name}, 'xtsite',
  'resolveConfiguredTheme__site_local_theme__is_recorded_at_startup';

test_psgi $app, sub {
  my $cb = shift;

  # Without a session AuthN rewrites the path to the login page, which also
  # answers 200, so the body is what proves the theme was served.
  my $res = $cb->(GET '/theme.css');
  like $res->content, qr/#123456/,
    'themeRoute__no_session__serves_the_theme_not_the_login_page';
  like $res->header('Content-Type'), qr{^text/css}, 'themeRoute__configured_theme__is_served_as_css';
};

done_testing;
