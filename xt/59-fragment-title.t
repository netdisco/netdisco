#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;

# htmx sets document.title from a <title> it finds at the top level of a
# swapped response, and until now nothing but the page layout emitted one, so
# every tab title came from netdisco.js reading the page it was replacing.
# App::Netdisco::Web's `after` hook now puts the title in the fragment itself.
#
# Two properties of htmx's makeFragment decide the assertions below. It lifts a
# <title> only when the element is a direct child of the parsed fragment, which
# is why the title must be the first bytes of the response and may not be
# wrapped; and it removes that element before the swap, which is why a pane
# whose body is empty must still carry one, or the tab would keep the title of
# whatever was shown before it.
#
# Why the guard is htmx's own header rather than any XHR is recorded beside the
# hook in App::Netdisco::Web; the last two subtests are what hold it.
#
# The probe routes are registered here rather than reused from lib/, so the
# test needs no database: every real pane route is behind require_login or
# require_role and the auth provider is DBIC, which is what confines xt/35 and
# xt/36 to source assertions. `no_auth` makes the AuthN `before` hook
# synthesize a guest session rather than rewrite path_info to '/', which is the
# same reason xt/57-route-cache-ajax.t sets it.
#
# The device case is deliberately not driven here. Its title needs a Device row
# and the duplicate-DNS count that decides between name and address, so it is
# covered by the visual harness instead. What is asserted below is the ordering
# that keeps it cheap: an unregistered tab is refused before any query runs.

BEGIN {
    $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;
use Dancer::Plugin::Ajax;

use App::Netdisco::Util::Web 'page_title';

setting('no_auth' => 1);
setting('branding_text' => 'Netdisco');
setting('_reports')->{'portlog'} = { tag => 'portlog', label => 'Port Log' };

# Dancer::Test's own `headers` argument never reaches Dancer::Request, so the
# CGI-style variable is what carries a header here. See xt/57.
# X-Requested-With goes with it because a Dancer::Plugin::Ajax route matches on
# that alone, and the page templates put both on every htmx request through
# hx-headers.
sub htmx_response {
    my ($path, $params) = @_;
    local $ENV{HTTP_HX_REQUEST} = 'true';
    local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
    return dancer_response(GET => $path, { params => ($params || {}) });
}

ajax '/ajax/content/search/xttitleprobe'      => sub { '' };
ajax '/ajax/content/admin/xttitleprobe'       => sub { '<div>one row</div>' };
ajax '/ajax/content/device/xttitleprobe'      => sub { '<div>one row</div>' };
ajax '/ajax/content/report/xttitleprobe/data' => sub { '[]' };
get  '/ajax/content/report/xttitleprobecsv'   => sub { 'a,b,c' };
get  '/ajax/xt-portlog-title' => sub { page_title('report', 'portlog') };

subtest 'ajax_content_fragment__pane_route__carries_the_tab_title' => sub {
    my $r = htmx_response('/ajax/content/admin/xttitleprobe');

    is $r->status, 200, 'the probe pane answers';
    is $r->content, '<title>Netdisco</title><div>one row</div>',
      'and the title is the first thing in the fragment, wrapped in nothing';
};

# A tenant URL reaches the same pane by forward, and Dancer runs an after hook
# once for the inner request and again for the response rebuilt from it. Two
# titles in one fragment is not cosmetic: htmx lifts and removes only the first,
# so the second is swapped into the pane as an element, and the empty-pane check
# in netdisco.js then never sees an empty pane.
subtest 'ajax_content_fragment__reached_through_a_tenant_prefix__carries_one_title' => sub {
    my $r = htmx_response('/t/xt/ajax/content/admin/xttitleprobe');

    is $r->content, '<title>Netdisco</title><div>one row</div>',
      'a forwarded request carries exactly the title a direct one does';
};

subtest 'ajax_content_fragment__empty_pane__still_carries_the_tab_title' => sub {
    my $r = htmx_response('/ajax/content/search/xttitleprobe');

    is $r->content, '<title>Netdisco</title>',
      'a pane with no results carries the title and nothing else';
};

subtest 'ajax_content_fragment__unregistered_device_tab__carries_no_title' => sub {
    my $r = htmx_response('/ajax/content/device/xttitleprobe');

    is $r->content, '<div>one row</div>',
      'an unknown device tab is refused before the device is looked up';
};

subtest 'ajax_content_fragment__endpoint_below_a_pane__carries_no_title' => sub {
    my $r = htmx_response('/ajax/content/report/xttitleprobe/data');

    is $r->content, '[]',
      'a deeper path is chart data or a download, and replaces no pane';
};

subtest 'ajax_content_fragment__not_from_htmx__carries_no_title' => sub {
    local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
    my $r = dancer_response(GET => '/ajax/content/report/xttitleprobecsv');

    is $r->content, 'a,b,c',
      'nothing but htmx acts on the title, so nothing else is given one';
};

subtest 'page_title__portlog_report__names_the_device_and_port_on_one_line' => sub {
    my $r = dancer_response(GET => '/ajax/xt-portlog-title',
      { params => { q => 'switch1.example.com', f => 'GigabitEthernet0/1' } });

    is $r->content, 'switch1.example.com - GigabitEthernet0/1 - Port Log',
      'the one report that names its subject beside the tab keeps that order';
};

done_testing;
