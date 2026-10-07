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
  foreach my $reserved (qw/light auto/) {
    open my $reserved_css, '>', catfile("$sitedir", 'themes', "$reserved.css")
      or die "cannot write the theme: $!";
    print $reserved_css "[data-bs-theme=\"$reserved\"] { --bs-primary: #654321; }\n";
    close $reserved_css;
  }

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

# The console logger prints to STDERR rather than calling warn.
sub stderr_of {
  my ($code) = @_;
  my $captured = File::Temp->new;
  open my $saved_stderr, '>&', \*STDERR or die "cannot save STDERR: $!";
  open STDERR, '>', "$captured" or die "cannot redirect STDERR: $!";
  $code->();
  open STDERR, '>&', $saved_stderr or die "cannot restore STDERR: $!";
  return do { local $/; open my $fh, '<', "$captured" or die $!; <$fh> };
}

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

setting(web_theme => 'light');
my $light_log = stderr_of(sub { App::Netdisco::Web::Theme::resolve_configured_theme() });
is setting('_web_theme'), undef, 'resolveConfiguredTheme__light__resolves_no_theme';
unlike $light_log, qr/web_theme is 'light'|not a valid theme/,
  'resolveConfiguredTheme__light__reports_no_problem';
test_psgi $app, sub {
  my $cb = shift;
  like $cb->(GET '/login')->content, qr/<html data-nd-theme-default="" /,
    'mainLayout__light__carries_an_empty_default';
};

foreach my $reserved (qw/light auto/) {
  like $light_log, qr/a site theme named '$reserved' was found at \S*\Q$reserved\E\.css, but '$reserved' is a reserved web_theme value and the file is not used\. Rename the file and set web_theme to the new name\./,
    "resolveConfiguredTheme__site_theme_named_$reserved\__warns_it_is_unused";
}

setting(web_theme => 'xtstock');
my $unreserved_log = stderr_of(sub { App::Netdisco::Web::Theme::resolve_configured_theme() });
like $unreserved_log, qr/a site theme named 'light' was found/,
  'resolveConfiguredTheme__other_theme_with_a_reserved_site_file__still_warns';

done_testing;
