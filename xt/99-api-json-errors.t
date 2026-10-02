#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

# Everything under /api answers in JSON, including its failures. Two did not:
# a path or method that matches no route fell through to the not-found page,
# and a route that died was rendered by Dancer::Error as an HTML error page.
# Both happened with Accept: application/json set, so a client that asked for
# JSON had markup to parse, usually as "unexpected character '<'".
#
# The browser answers are asserted as well, since both changes sit on paths
# every request can reach and must only answer differently for the API.
#
# Only the DB edges are faked: the token, the roles, and a schema that dies so
# that a route crashes the way it would with the database gone.

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Web;
use App::Netdisco::Web::Auth::Provider::DBIC;
use Dancer ':tests';
use Dancer::Test;

package FakeUser;
sub new      { return bless { username => $_[1] }, $_[0] }
sub username { return $_[0]->{username} }

package main;

no warnings 'redefine';
*App::Netdisco::Web::Auth::Provider::DBIC::validate_api_token = sub { FakeUser->new('admin') };
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'admin' } };
*Dancer::Plugin::Auth::Extensible::user_roles = sub {
  my @r = qw/api api_admin admin/; return wantarray ? @r : [@r] };
*App::Netdisco::Web::API::Queue::schema = sub { die "secret detail from the database\n" };

# see xt/97: Dancer::Test does not reset the cookie jar between requests
sub fresh_request { Dancer::Cookies->init; return dancer_response(@_) }
sub body_of { my $b = (shift)->content; $b = do { local $/; <$b> } if ref $b; return $b // '' }

my @api = ('Authorization' => 'token', 'Accept' => 'application/json');

my $missing = fresh_request(GET => '/api/v1/no/such/endpoint', { headers => [@api] });
is $missing->status, 404, 'an unknown API path is not found';
like body_of($missing), qr/\A\s*\{.*"error"\s*:\s*"not found"/s, 'and says so in JSON';

my $method = fresh_request(PATCH => '/api/v1/queue/status', { headers => [@api] });
is $method->status, 404, 'a known API path with a method it lacks is not found';
like body_of($method), qr/\A\s*\{/, 'also in JSON';

my $crash = fresh_request(GET => '/api/v1/queue/status', { headers => [@api] });
is $crash->status, 500, 'a route that dies is a server error';
like $crash->header('Content-Type'), qr{application/json}, 'served as JSON';
like body_of($crash), qr/"error"\s*:\s*"internal server error"/, 'naming the status';
unlike body_of($crash), qr/secret detail/, 'and not the exception, which stays in the log';

# a browser still gets a page (the login page here, as it has no session)
my $page = fresh_request(GET => '/no/such/page');
like body_of($page), qr/<html/i, 'a browser still gets a page, not JSON';

done_testing;
