#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

# A theme file found by name whose rules use another name loads but changes
# nothing, so startup says so.
my ($envdir, $sitedir);
BEGIN {
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');

  $sitedir = File::Temp->newdir(CLEANUP => 1);
  mkdir catdir("$sitedir", 'themes') or die "cannot make themes dir: $!";
  open my $css, '>', catfile("$sitedir", 'themes', 'xtscope.css')
    or die "cannot write the theme: $!";
  print $css "[data-bs-theme=\"somethingelse\"] { --bs-primary: #123456; }\n";
  close $css;

  $envdir = File::Temp->newdir(CLEANUP => 1);
  open my $env, '>', catfile("$envdir", 'testing.yml')
    or die "cannot write the test environment file: $!";
  print $env "web_theme: 'xtscope'\ntemplate_paths: ['$sitedir']\n";
  close $env;

  $ENV{DANCER_ENVDIR} = "$envdir";
  $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use Plack::Util;

# The console logger prints to STDERR rather than calling warn.
my $stderr_file = File::Temp->new;
open my $saved_stderr, '>&', \*STDERR or die "cannot save STDERR: $!";
open STDERR, '>', "$stderr_file" or die "cannot redirect STDERR: $!";
my $psgi = catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg');
my $app  = eval { Plack::Util::load_psgi($psgi) };
open STDERR, '>&', $saved_stderr or die "cannot restore STDERR: $!";
BAIL_OUT("could not load $psgi: $@") unless $app;

my $logged = do { local $/; open my $fh, '<', "$stderr_file" or die $!; <$fh> };

sub setting { return Dancer::Config::setting(@_) }

like $logged, qr/web_theme 'xtscope'.*\[data-bs-theme="xtscope"\]/,
  'resolveConfiguredTheme__rules_scoped_to_another_name__warns_at_startup';
is +(setting('_web_theme') || {})->{name}, 'xtscope',
  'resolveConfiguredTheme__rules_scoped_to_another_name__still_loads_the_file';

done_testing;
