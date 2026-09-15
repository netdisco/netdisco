#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;

# The tenant segment of a /t/<tenant>/... URL becomes a Dancer var, is
# appended to the uri_base template token, and is written into href and src
# attributes by the main layout and the SNMP panes through the `none` filter,
# which turns off the escaping the rest of the page relies on. Only a
# configured tenancy may set it, and it is escaped where uri_base is built.
#
# The check belongs in the routes rather than in the layout because uri_base
# reaches several unfiltered sinks, and because a tenancy that is not
# configured has no database behind it to serve anyway.
#
# `no_auth` is what makes this a request-level test rather than a source
# assertion. AuthN's before hook rewrites path_info to '/' for a request
# carrying no session, so neither /t/ route would be reached and the test would
# pass on code that still has the defect. It synthesizes a guest session
# without a user row (see App::Netdisco::Web::Auth::Provider::DBIC), and every
# path asserted here renders from configuration and templates alone, so no
# database is involved.

BEGIN {
    $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;

setting('no_auth' => 1);

subtest 'tenant_tags__shipped_configuration__holds_the_primary_tenancy' => sub {
    # the list is built at startup from tenant_databases plus the primary
    # tenancy, and a site config the tests inherit may add to it, so this says
    # where the list comes from rather than what else is in it.
    ok scalar( grep { $_ eq 'netdisco' } @{ setting('tenant_tags') } ),
      'the tenancy list the routes are checked against';
};

subtest 'tenant_route__configured_tenant__keeps_the_tenant_in_page_links' => sub {
    my $response = dancer_response(GET => '/t/netdisco/');

    is $response->status, 200, 'the front page of a configured tenancy is served';
    like $response->content, qr{\Qhref="/t/netdisco/images/favicon.ico"\E},
      'and its links are built under the tenant path';
};

subtest 'tenant_route__configured_tenant_with_a_path__keeps_the_tenant_in_page_links' => sub {
    my $response = dancer_response(GET => '/t/netdisco/login');

    is $response->status, 200, 'a page below a configured tenancy is served';
    like $response->content, qr{\Qhref="/t/netdisco/images/favicon.ico"\E},
      'and its links are built under the tenant path';
};

subtest 'tenant_route__tag_added_to_the_tenancy_list__is_served_like_the_primary' => sub {
    # without a second tag, code checking for the primary tenancy by name
    # would pass every assertion in this file.
    push @{ setting('tenant_tags') }, 'xt-second-site';
    my $response = dancer_response(GET => '/t/xt-second-site/login');
    pop @{ setting('tenant_tags') };

    is $response->status, 200, 'any configured tenancy is served';
    like $response->content, qr{\Qhref="/t/xt-second-site/images/favicon.ico"\E},
      'and its links are built under its own tenant path';
};

subtest 'tenant_route__tag_needing_escaping__is_percent_escaped_in_page_links' => sub {
    push @{ setting('tenant_tags') }, 'xt second site';
    my $response = dancer_response(GET => '/t/xt second site/login');
    pop @{ setting('tenant_tags') };

    like $response->content, qr{\Qhref="/t/xt%20second%20site/images/favicon.ico"\E},
      'a tag is escaped for the URL it is written into';
};

subtest 'tenant_route__unknown_tenant__is_not_reflected_into_the_page' => sub {
    my $response = dancer_response(GET => '/t/bogus/');

    is $response->status, 404, 'a tenancy that is not configured is not a page';
    unlike $response->content, qr{/t/bogus},
      'and the segment reaches no link in the page';
    like $response->content, qr{\Qhref="/images/favicon.ico"\E},
      'which are built without a tenant';
};

subtest 'tenant_route__unknown_tenant_with_a_path__is_not_reflected_into_the_page' => sub {
    my $response = dancer_response(GET => '/t/bogus/login');

    is $response->status, 404, 'a path below it is not a page either';
    unlike $response->content, qr{/t/bogus},
      'and the segment reaches no link in the page';

    my $posted = dancer_response(POST => '/t/bogus/login');

    is $posted->status, 404, 'and neither route is method specific';
};

subtest 'tenant_route__markup_in_the_segment__does_not_reach_the_document_head' => sub {
    # closes an attribute and opens a tag, the shape the `none` filter lets by
    my $segment = '"><b>';
    my $response = dancer_response(GET => "/t/$segment/");

    is $response->status, 404, 'markup is not a configured tenancy';
    unlike $response->content, qr{\Q$segment\E},
      'so it is never written into the page';
    like $response->content, qr{\Qhref="/images/favicon.ico"\E},
      'and the head carries the links it would have broken out of';
};

done_testing;
