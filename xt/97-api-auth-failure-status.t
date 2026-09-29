#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

# A valid API token whose user lacks the role an endpoint requires used to get
# a 302 to /login/denied, the redirect require_role gives a browser. A client
# cannot tell that apart from a broken token or a moved endpoint, and one that
# follows it re-asks a page it never meant to, while the call it made did
# nothing. Two separate clients hit this against the queue endpoints before
# anyone noticed the token was simply not an admin's.
#
# Only the DB edges are faked: the token lookup, the user row, and the roles
# the provider would read from the user_role view. The before hook, the
# require_role wrapper and the permission_denied hook are the real ones.
#
# The browser case is asserted too, because the hook sits in front of the
# redirect for every request and must only answer for the API.
#
# The same file covers a request that sends no credentials at all. The before
# hook sends those to the handler for '/', which recognises the API by the
# Accept header alone, so a client without one got the login page as HTML with
# a 200 and a JSON Content-Type, which it took for success.

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Web;
# loaded now so that its subs exist to be replaced; the auth plugin would
# otherwise require it on the first request and put the real ones back
use App::Netdisco::Web::Auth::Provider::DBIC;
use Dancer ':tests';
use Dancer::Test;

package FakeUser;
sub new      { return bless { username => $_[1] }, $_[0] }
sub username { return $_[0]->{username} }

package main;

my @roles = ('api'); # a valid token, but not an admin's

no warnings 'redefine';
*App::Netdisco::Web::Auth::Provider::DBIC::validate_api_token = sub {
  return ($_[1] eq 'goodtoken' ? FakeUser->new('apiuser') : undef);
};
*App::Netdisco::Web::Auth::Provider::DBIC::get_user_details = sub {
  return FakeUser->new($_[1]);
};
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'apiuser' } };
*Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? @roles : [@roles] };

# Dancer::Handler resets the cookie jar at the start of every request and
# Dancer::Test does not, so without this a session set up by one request here
# would authenticate the next, which a real server never does.
sub fresh_request { Dancer::Cookies->init; return dancer_response(@_) }

# queue/status is guarded by require_role api_admin and needs nothing else
my $api = fresh_request(GET => '/api/v1/queue/status', { headers => [
  'Authorization' => 'goodtoken', 'Accept' => 'application/json' ] });

is $api->status, 403, 'a valid token without the role is forbidden';
is $api->header('Location'), undef, 'and is not redirected anywhere';
like $api->content, qr{"error"\s*:\s*"insufficient role},
  'with a JSON body that says why';

# a bad token is a different fault and keeps its own answer
my $bad = fresh_request(GET => '/api/v1/queue/status', { headers => [
  'Authorization' => 'badtoken', 'Accept' => 'application/json' ] });
is $bad->status, 401, 'an invalid token is still unauthorized, not forbidden';
like $bad->content, qr/"error"\s*:\s*"invalid or expired token"/,
  'and says why, where it used to send an empty body';

# no credentials at all, with and without an Accept header
foreach my $accept ([], ['Accept' => 'application/json']) {
  my $what = (@$accept ? 'with' : 'without') . ' an Accept header';
  my $none = fresh_request(GET => '/api/v1/queue/status', { headers => $accept });
  is $none->status, 401, "no credentials $what is unauthorized";
  my $body = $none->content; $body = do { local $/; <$body> } if ref $body;
  like $body, qr/\A\s*\{.*"error"\s*:\s*"not authorized"/s, "and says so in JSON $what";
}

# a browser that lacks the role still goes to the denied page as before
# (an existing admin-only route; one defined here would lose to Web.pm's
# catch-all, which is registered first)
set trust_x_remote_user => 1;

my $web = fresh_request(GET => '/ajax/content/admin/snapshot_get', { headers => [
  'X-REMOTE_USER' => 'webuser' ] });
is $web->status, 302, 'a browser without the role is still redirected';
like $web->header('Location'), qr{/login/denied}, 'to the denied page';

done_testing;
