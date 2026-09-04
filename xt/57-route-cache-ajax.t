#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;

# Dancer::App::find_route caches whichever route matches a path, keyed only on
# method and path (Dancer::Route::Cache::store_path). An ajax route from
# Dancer::Plugin::Ajax carries a {ajax => 1} route option and is skipped by a
# non-XHR request, so that request falls through to the next matching route:
# App::Netdisco::Web's catch-all, `any qr{.*}`, which renders the 404 page.
# With the cache on, that 404 is what gets stored for the path. Every later
# XHR request to the same path is then answered from the cache, with the same
# 404, never reaching the ajax handler at all.
#
# The probe route is registered here rather than reused from lib/, so the
# test needs no database and no fixture device: nothing else can have already
# cached this path before the assertions below run.
#
# `no_auth` is required rather than merely convenient. AuthN's `before` hook
# rewrites path_info to '/' for a request carrying no session, which would
# route both requests to the front page and never reach either the ajax
# handler or the catch-all: the test would then pass on code that still has
# the defect. `no_auth` makes that hook synthesize a guest session on every
# request instead, without needing a user row in the database (see
# App::Netdisco::Web::Auth::Provider::DBIC::get_user_details).
#
# THIS FILE IS A REQUEST-LEVEL TEST, where xt/35 and xt/36 could only assert
# against source: this path carries no `require_role`, so the DBIC auth
# provider that puts protected routes out of reach never comes into play.

BEGIN {
    $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;
use Dancer::Plugin::Ajax;

setting('route_cache' => 1);
setting('no_auth'     => 1);

ajax '/ajax/xt-route-cache-probe' => sub { 'probe reached' };

subtest 'ajax_route__plain_request_first__still_answers_the_xhr_that_follows' => sub {
    my $plain = dancer_response(GET => '/ajax/xt-route-cache-probe');
    is $plain->status, 404,
      'a plain request does not reach an ajax route, and falls through instead';

    # Dancer::Test's own header list, keyed by name with underscores, never
    # matches HTTP::Headers' internal keys, which use dashes: passing
    # X-Requested-With through the documented `headers` argument to
    # dancer_response is silently dropped before the request is built. Setting
    # the CGI-style environment variable directly is what actually reaches
    # Dancer::Request, the same way a real PSGI server would provide it.
    local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
    my $xhr = dancer_response(GET => '/ajax/xt-route-cache-probe');

    is $xhr->status, 200,
      'and the ajax route still answers the XHR request that follows';
    like $xhr->content, qr/probe reached/,
      'because it is the ajax handler that runs, not the cached catch-all';
};

done_testing;
