#!/usr/bin/env perl

use strict;
use warnings;

# xt/40 snapshots index.tt only in its logged in state, where the login form
# does not exist, so nothing there covers this markup.
#
# The first subtest is load bearing: without it, a stash that stopped reaching
# the login form would leave the rest passing against markup never emitted.

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template/;

my $logo = '/images/example-logo.png';

my ($html, $error) = render_template('index.tt', {
  session  => {},
  settings => { login_logo => $logo },
});

is $error, undef, 'loginPage__logged_out_stash__renders_without_error';

subtest 'loginPage__logged_out_stash__reaches_the_login_form' => sub {
    like $html, qr/class="nd_login-form"/, 'the login form is present';
    like $html, qr/name="password"/,
      'the password field distinguishes it from the discover box';
    like $html, qr/\Q$logo\E/, 'the configured logo is rendered';
};

subtest 'loginLogo__a_logo_too_wide_for_the_row__may_wrap_below_the_fields' => sub {
    my ($row) = ($html =~ m/<form class="nd_login-form".*?<div class="([^"]*)"/s);
    ok defined $row, 'the login form opens with a row container'
      or diag 'no row container in the rendered login form';
    like $row, qr/\bd-flex\b/, 'the row is a flex container';
    like $row, qr/\bflex-wrap\b/, 'the row wraps';
};

subtest 'loginLogo__wider_than_its_container__is_held_inside_it' => sub {
    my ($img) = ($html =~ m/<img([^>]*\Q$logo\E[^>]*)>/);
    ok defined $img, 'the logo image tag is rendered'
      or diag 'no logo img tag in the rendered login form';
    like $img, qr/\bimg-fluid\b/, 'the logo is bounded by its container';
};

done_testing;
