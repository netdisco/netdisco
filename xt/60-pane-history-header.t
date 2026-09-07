#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;

# htmx puts the value of HX-Push-Url or HX-Replace-Url in the address bar, and
# reads the literal value "false" as an instruction to leave the history
# alone, so a pane response can say what its own address is. The browser has
# been doing this for itself, and the granularity it settled on is not
# uniform: a device or search tab change is a new history entry where a change
# to that tab's options is not, a report makes an entry for every submission,
# and an admin task makes none at all. The assertions below pin each of those.
#
# The value is built from uri_for, which carries the tenant prefix, and the
# request's raw QUERY_STRING, which is what the sidebar form serialized. The
# my_query token cannot be used: it stringifies a repeated parameter as an
# array reference.
#
# Where the rule differs from the browser's: the browser knows a tab change
# from the click that caused it, and the server knows it from the tab of the
# address htmx says it is leaving. The two agree, because the browser reaches
# a pane of another tab only by clicking its link.
#
# The probe routes are registered here rather than reused from lib/, so the
# test needs no database: every real pane route is behind require_login or
# require_role and the auth provider is DBIC. `no_auth` makes the AuthN
# `before` hook synthesize a guest session rather than rewrite path_info to
# '/', which is the same reason xt/57-route-cache-ajax.t sets it.

BEGIN {
    $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;
use Dancer::Plugin::Ajax;

setting('no_auth' => 1);
setting('branding_text' => 'Netdisco');

# Dancer::Test's own `headers` argument never reaches Dancer::Request, so the
# CGI-style variable is what carries a header here. See xt/57 and xt/59.
sub pane_response {
    my ($path, $current) = @_;
    local $ENV{HTTP_HX_REQUEST} = 'true';
    local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
    local $ENV{HTTP_HX_CURRENT_URL} = $current if defined $current;
    return dancer_response(GET => $path);
}

sub history_header {
    my $r = shift;
    return ('HX-Push-Url' => $r->header('HX-Push-Url'))
      if defined $r->header('HX-Push-Url');
    return ('HX-Replace-Url' => $r->header('HX-Replace-Url'))
      if defined $r->header('HX-Replace-Url');
    return ();
}

ajax '/ajax/content/device/xthistoryprobe'      => sub { '' };
ajax '/ajax/content/search/xthistoryprobe'      => sub { '' };
ajax '/ajax/content/report/xthistoryprobe'      => sub { '' };
ajax '/ajax/content/admin/xthistoryprobe'       => sub { '' };
ajax '/ajax/content/report/xthistoryprobe/data' => sub { '[]' };

subtest 'pane_response__device_options_changed__replaces_the_address' => sub {
    my $r = pane_response('/ajax/content/device/xthistoryprobe?tab=xthistoryprobe&q=switch1',
      'http://localhost/device?tab=xthistoryprobe&q=switch0');

    is_deeply [ history_header($r) ],
      [ 'HX-Replace-Url' => '/device?tab=xthistoryprobe&q=switch1' ],
      'the tab is the one already shown, so its options replace the entry';
};

subtest 'pane_response__device_tab_changed__pushes_the_address' => sub {
    my $r = pane_response('/ajax/content/device/xthistoryprobe?tab=xthistoryprobe&q=switch1',
      'http://localhost/device?tab=ports&q=switch1');

    is_deeply [ history_header($r) ],
      [ 'HX-Push-Url' => '/device?tab=xthistoryprobe&q=switch1' ],
      'a different tab is a new page, and the address is the page not the pane';
};

subtest 'pane_response__search_tab_changed__pushes_the_address' => sub {
    my $r = pane_response('/ajax/content/search/xthistoryprobe?tab=xthistoryprobe&q=00:11:22:33:44:55',
      'http://localhost/search?tab=node&q=00:11:22:33:44:55');

    is_deeply [ history_header($r) ],
      [ 'HX-Push-Url' => '/search?tab=xthistoryprobe&q=00:11:22:33:44:55' ],
      'search decides the same way device does';
};

# The first request a page makes is its own tab's, and nothing has been left.
subtest 'pane_response__address_names_no_tab__replaces_the_address' => sub {
    my $r = pane_response('/ajax/content/device/xthistoryprobe?tab=xthistoryprobe&q=switch1',
      'http://localhost/device?q=switch1');

    is_deeply [ history_header($r) ],
      [ 'HX-Replace-Url' => '/device?tab=xthistoryprobe&q=switch1' ],
      'an address with no tab is where the page landed, not a tab being left';
};

subtest 'pane_response__no_current_address__replaces_the_address' => sub {
    my $r = pane_response('/ajax/content/device/xthistoryprobe?tab=xthistoryprobe');

    is_deeply [ history_header($r) ],
      [ 'HX-Replace-Url' => '/device?tab=xthistoryprobe' ],
      'without HX-Current-URL nothing is known to have changed';
};

# The Ports sidebar sends one parameter per column, all named c_*, and the
# device form repeats q on some pages. The raw query string carries every
# repetition, where the my_query token collapses them into ARRAY(0x...).
subtest 'pane_response__repeated_parameter__is_carried_verbatim' => sub {
    my $r = pane_response('/ajax/content/device/xthistoryprobe?tab=xthistoryprobe&c_port=on&c_name=on',
      'http://localhost/device?tab=xthistoryprobe');

    is_deeply [ history_header($r) ],
      [ 'HX-Replace-Url' => '/device?tab=xthistoryprobe&c_port=on&c_name=on' ],
      'the address carries the query the form serialized, in its order';
};

subtest 'pane_response__reached_through_a_tenant_prefix__addresses_the_tenant' => sub {
    my $r = pane_response('/t/xt/ajax/content/device/xthistoryprobe?tab=xthistoryprobe',
      'http://localhost/t/xt/device?tab=ports');

    is_deeply [ history_header($r) ],
      [ 'HX-Push-Url' => '/t/xt/device?tab=xthistoryprobe' ],
      'the address is the tenant page, which uri_for is monkeypatched to give';
};

subtest 'pane_response__report_options_changed__pushes_the_address' => sub {
    my $r = pane_response('/ajax/content/report/xthistoryprobe?age_num=3',
      'http://localhost/report/xthistoryprobe?age_num=1');

    is_deeply [ history_header($r) ],
      [ 'HX-Push-Url' => '/report/xthistoryprobe?age_num=3' ],
      'a report makes an entry for every submission, and names its own tab';
};

# The browser's guard against repeating the address it is already showing
# compares the whole target, query included, against location.pathname, so it
# holds only for a report whose sidebar has nothing to serialize. Reproduced
# rather than corrected: any report with an option pushes an entry duplicating
# the one it is on, which the Back button then appears to ignore once.
subtest 'pane_response__report_repeating_an_empty_query__leaves_history_alone' => sub {
    my $r = pane_response('/ajax/content/report/xthistoryprobe',
      'http://localhost/report/xthistoryprobe');

    is_deeply [ history_header($r) ], [ 'HX-Push-Url' => 'false' ],
      'nothing has changed, so nothing is added';
};

subtest 'pane_response__report_arrived_at_from_elsewhere__pushes_the_address' => sub {
    my $r = pane_response('/ajax/content/report/xthistoryprobe',
      'http://localhost/report/somethingelse');

    is_deeply [ history_header($r) ],
      [ 'HX-Push-Url' => '/report/xthistoryprobe' ],
      'an empty query is still a page of its own when it is a different page';
};

# "false" rather than no header at all: htmx reads the header before any
# hx-push-url attribute, so only the header can overrule one, and the shared
# tab element these forms sit under is about to carry inherited attributes.
subtest 'pane_response__admin_task__leaves_history_alone' => sub {
    my $r = pane_response('/ajax/content/admin/xthistoryprobe?acl_name=core',
      'http://localhost/admin/xthistoryprobe');

    is_deeply [ history_header($r) ], [ 'HX-Push-Url' => 'false' ],
      'an admin task has no address of its own, and the job queue refetches on a timer';
};

subtest 'pane_response__endpoint_below_a_pane__sets_no_header' => sub {
    my $r = pane_response('/ajax/content/report/xthistoryprobe/data?age_num=3',
      'http://localhost/report/xthistoryprobe');

    is_deeply [ history_header($r) ], [],
      'a deeper path is chart data or a download, and replaces no pane';
};

subtest 'pane_response__not_from_htmx__sets_no_header' => sub {
    local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
    my $r = dancer_response(GET => '/ajax/content/report/xthistoryprobe?age_num=3');

    is_deeply [ history_header($r) ], [],
      'nothing but htmx acts on the header, so nothing else is given one';
};

done_testing;
