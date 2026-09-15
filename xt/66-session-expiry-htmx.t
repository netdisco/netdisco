#!/usr/bin/env perl

use strict;
use warnings;

# An expired session reaches the reader as a way back in, not as a fault to
# report: "Search failed! Please contact your site administrator (server
# error)" sends them to an administrator over something they can fix by
# logging in again.
#
# The cause is that the unauthorized handler recognised only X-Requested-With.
# htmx sends HX-Request and does not send that header, so a pane request fell
# through to the branch that renders the whole login page, and htmx swapped a
# password form into the pane with a 200. The two site-local failure modes are
# opposite and both silent, which is why all three branches are asserted here
# rather than only the new one.
#
# This is a request-level test, unlike xt/35 and xt/36 which are source
# assertions. It can be, because the route under test is the one that answers
# when there is no session, so nothing here reaches the DBIC auth provider.

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Web;
use Dancer ':tests';
use Dancer::Test;

my $PAGE = 'http://netdisco.example/admin/jobqueue?tab=jobqueue';

my $htmx = dancer_response(GET => '/login/denied', { headers => [
  'HX-Request' => 'true', 'HX-Current-URL' => $PAGE ] });

is $htmx->status, 401, 'an htmx request with no session is unauthorized';
like $htmx->header('HX-Redirect'), qr{^/login\?return_url=},
  'and is sent to the login page by the header htmx acts on';
like $htmx->header('HX-Redirect'), qr{admin%2Fjobqueue},
  'carrying the page the reader was on, not the pane path';
is length($htmx->content // ''), 0,
  'with no body, so nothing is swapped into the pane on the way out';

# The pane path htmx would have asked for is not somewhere to send a reader:
# it renders a fragment with no chrome. HX-Current-URL is the address bar.
unlike $htmx->header('HX-Redirect'), qr{ajax},
  'never back to the fragment itself';

# jQuery still makes requests here, and they must keep the answer they had.
my $xhr = dancer_response(GET => '/login/denied', { headers => [
  'X-Requested-With' => 'XMLHttpRequest' ] });

is $xhr->status, 401, 'an XHR with no session is still unauthorized';
is $xhr->header('HX-Redirect'), undef, 'and is not redirected by htmx headers';
like $xhr->content, qr{unauthorized}, 'it still gets the short message';

# A person typing the address gets the login form, which is the whole point of
# the branch the htmx one now sits in front of.
my $plain = dancer_response(GET => '/login/denied');
is $plain->status, 200, 'a plain request still renders the login page';
like $plain->content, qr{name="password"}, 'with a form to log in with';

done_testing;
