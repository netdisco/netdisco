#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

# A page can load any theme a preference source picks, without login, and the
# name never reaches outside the theme directories. The login exemption is no
# wider than the route, so a path the route would not serve still needs login.

my ($envdir, $sitedir);
BEGIN {
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');

  $sitedir = File::Temp->newdir(CLEANUP => 1);
  mkdir catdir("$sitedir", 'themes') or die "cannot make themes dir: $!";
  open my $css, '>', catfile("$sitedir", 'themes', 'xtsite.css')
    or die "cannot write the theme: $!";
  print $css "[data-bs-theme=\"xtsite\"] { --bs-primary: #123456; }\n";
  close $css;
  foreach my $reserved (qw/light auto/) {
    open my $reserved_css, '>', catfile("$sitedir", 'themes', "$reserved.css")
      or die "cannot write the theme: $!";
    print $reserved_css "[data-bs-theme=\"$reserved\"] { --bs-primary: #654321; }\n";
    close $reserved_css;
  }

  $envdir = File::Temp->newdir(CLEANUP => 1);
  open my $env, '>', catfile("$envdir", 'testing.yml')
    or die "cannot write the test environment file: $!";
  print $env "template_paths: ['$sitedir']\n";
  close $env;
  $ENV{DANCER_ENVDIR} = "$envdir";
  $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;

my $app = eval { Plack::Util::load_psgi(catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg')) };
BAIL_OUT("could not load the web app: $@") unless $app;

test_psgi $app, sub {
  my $cb = shift;

  my $dark = $cb->(GET '/theme/dark.css');
  is $dark->code, 200, 'themeByName__shipped_theme__is_served';
  like $dark->header('Content-Type'), qr{\Atext/css}, 'themeByName__shipped_theme__is_css';
  is $cb->(GET '/theme/xtsite.css')->code, 200, 'themeByName__site_theme__is_served';

  my $missing = $cb->(GET '/theme/nosuch.css');
  is $missing->code, 404, 'themeByName__unknown_name__is_not_found_without_login';
  is $missing->content, '', 'themeByName__not_found__has_an_empty_body';
  foreach my $reserved (qw/light auto/) {
    my $response = $cb->(GET "/theme/$reserved.css");
    is $response->code, 404, "themeByName__reserved_name_$reserved\__is_not_found_despite_a_site_file";
    is $response->content, '', "themeByName__reserved_name_$reserved\__has_an_empty_body";
  }

  # Outside the exemption, so the login page answers; the point is no CSS.
  foreach my $path ('/theme/..%2Fnetdisco.css', '/theme/a.b.css', '/theme/x/y.css', '/theme/dark.css.bak') {
    my $response = $cb->(GET $path);
    unlike $response->header('Content-Type') // '', qr{text/css},
      "themeByName__path_$path\__is_not_served_as_css";
    isnt $response->code, 404, "themeByName__path_$path\__is_not_exempt_from_login";
  }
};

done_testing;
