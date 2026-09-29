#!/usr/bin/env perl

# The shipped helper is called here rather than reimplemented, so the cases
# below exercise what the login route actually redirects to.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing' }

use Test::More 0.88;
use File::Slurper 'read_text';
use App::Netdisco;
use App::Netdisco::Web::AuthN;

sub redirect_target { App::Netdisco::Web::AuthN::safe_return_url(shift) }

subtest 'returnUrl__an_absolute_url_elsewhere__redirects_within_this_site' => sub {
  is redirect_target('https://elsewhere.example/x'), '/x', 'a scheme and host are dropped';
  is redirect_target('//elsewhere.example/x'), '/x', 'a protocol relative url is dropped';
  is redirect_target('////elsewhere.example/x'), '/elsewhere.example/x',
    'extra leading slashes do not survive as a host';
  unlike redirect_target('////elsewhere.example/x'), qr{^//},
    'the target cannot begin with two slashes';
};

subtest 'returnUrl__an_ordinary_path__is_unchanged' => sub {
  is redirect_target('/search?tab=node&q=1'), '/search?tab=node&q=1', 'path and query kept';
  is redirect_target('/device'), '/device', 'a bare path is kept';
  is redirect_target(''), '/', 'nothing becomes the front page';
  is redirect_target(undef), '/', 'undef becomes the front page';
};

subtest 'loginRoute__the_collapse__is_applied_to_the_redirect_target' => sub {
  my $src = read_text('lib/App/Netdisco/Web/AuthN.pm');
  like $src, qr/redirect safe_return_url\(param\('return_url'\)\)/,
    'the login route redirects to the checked target, not the raw parameter';
};

done_testing;
