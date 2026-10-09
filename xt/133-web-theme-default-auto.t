#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

# Checks that a site with no web_theme gets auto, which follows the browser's
# light or dark setting. The environment file sets no theme, so the value comes
# from config.yml.
my $envdir;
BEGIN {
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');

  $envdir = File::Temp->newdir(CLEANUP => 1);
  open my $env, '>', catfile("$envdir", 'testing.yml')
    or die "cannot write the test environment file: $!";
  print $env "log: 'warning'\n";
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

is setting('web_theme'), 'auto', 'configYml__no_web_theme__defaults_to_auto';
is +(setting('_web_theme') || {})->{name}, 'auto',
  'resolveConfiguredTheme__no_web_theme__resolves_auto';

test_psgi $app, sub {
  my $cb = shift;
  my $login = $cb->(GET '/login')->content;
  like $login, qr/<html data-nd-theme-default="auto" /,
    'loginPage__no_web_theme__leaves_the_color_mode_to_the_resolver';
  like $login, qr{/theme\.css\?v=\d+"}, 'loginPage__no_web_theme__links_the_dark_sheet';
  like $cb->(GET '/theme.css')->content, qr/data-bs-theme="dark"/,
    'themeRoute__no_web_theme__serves_the_dark_sheet';
};

done_testing;
