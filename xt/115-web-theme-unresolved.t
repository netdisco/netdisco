#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

my $envdir;
BEGIN {
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');
  $envdir = File::Temp->newdir(CLEANUP => 1);
  open my $env, '>', catfile("$envdir", 'testing.yml')
    or die "cannot write the test environment file: $!";
  print $env "web_theme: 'no-such-theme'\n";
  close $env;
  $ENV{DANCER_ENVDIR} = "$envdir";
  $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;

# The console logger prints to STDERR rather than calling warn, so the startup
# warning is captured by redirecting the handle around the app load.
my $stderr_file = File::Temp->new;
open my $saved_stderr, '>&', \*STDERR or die "cannot save STDERR: $!";
open STDERR, '>', "$stderr_file" or die "cannot redirect STDERR: $!";
my $psgi = catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg');
my $app  = eval { Plack::Util::load_psgi($psgi) };
open STDERR, '>&', $saved_stderr or die "cannot restore STDERR: $!";
BAIL_OUT("could not load $psgi: $@") unless $app;

my $logged = do { local $/; open my $fh, '<', "$stderr_file" or die $!; <$fh> };

sub setting { return Dancer::Config::setting(@_) }

like $logged, qr/web_theme is 'no-such-theme' but no no-such-theme\.css was found/,
  'resolveConfiguredTheme__unknown_name__warns_at_startup';
is setting('_web_theme'), undef,
  'resolveConfiguredTheme__unknown_name__falls_back_to_the_default_palette';

test_psgi $app, sub {
  my $cb = shift;
  is $cb->(GET '/theme.css')->code, 404,
    'themeRoute__no_resolved_theme__answers_not_found';

  # Reachable without a login, so it must not render the error page that
  # lists the application's settings when show_errors is on.
  setting('show_errors' => 1);
  is $cb->(GET '/theme.css')->content, '',
    'themeRoute__no_resolved_theme__answers_with_an_empty_body_even_with_show_errors';
};

done_testing;
