#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;

# The chrome around a pane that changes with the tab, the CSV download link and
# the device page's sidebar reset link, now arrives with the pane as
# hx-swap-oob markup instead of being rebuilt in the browser after every swap.
#
# Two properties of htmx's out-of-band handling decide the assertions below. It
# resolves the element by the id the response gives it, so the ids here have to
# be the ids the four page shells render, which is what the last subtest holds;
# and an element naming an id the page does not have is dropped with nothing but
# a console error, so a tab whose shell renders no anchor must be given no
# element at all. That is why the report and admin cases assert an absence.
#
# The device cases call the helper rather than a pane route. Their tags are
# fixed, the real routes for them are behind require_login with a DBIC auth
# provider, and page_title looks a device up by name; xt/59 records the same
# constraint. The tags the other cases use are registered here for the same
# reason, so that nothing depends on which web plugins the environment loads.

BEGIN {
    $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;
use Dancer::Plugin::Ajax;

use App::Netdisco::Util::Web 'pane_chrome';
use File::Slurper 'read_text';

setting('no_auth' => 1);
setting('branding_text' => 'Netdisco');

# the /t/ routes serve configured tenancies alone, so this tag must be one
push @{ setting('tenant_tags') }, 'xt';

setting('_device_tabs' => [
  { tag => 'ports',        label => 'Ports', provides_csv => 1 },
  { tag => 'netmap',       label => 'Neighbors' },
  { tag => 'details',      label => 'Details' },
  { tag => 'xtchromeprobe', label => 'Probe' },
]);
setting('_reports' => {
  xtchromecsv   => { tag => 'xtchromecsv',   label => 'With CSV', provides_csv => 1 },
  xtchromenocsv => { tag => 'xtchromenocsv', label => 'Without CSV' },
});
setting('_admin_tasks' => {
  xtchrometask => { tag => 'xtchrometask', label => 'Task', provides_csv => 1 },
  jobqueue     => { tag => 'jobqueue',     label => 'Job Queue', provides_csv => 1 },
});

# Dancer::Test's own `headers` argument never reaches Dancer::Request, so the
# CGI-style variable is what carries a header here. See xt/57, xt/59 and xt/60.
sub pane_response {
    my $path = shift;
    local $ENV{HTTP_HX_REQUEST} = 'true';
    local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
    return dancer_response(GET => $path);
}

my $CSV_ICON = '<i id="nd_csv-download-icon" class="text-info far fa-file-lines fa-lg"'
  .' rel="tooltip" data-bs-placement="left" data-bs-title="Download as CSV"></i>';
my $RESET_ICON = '<i class="nd_sidebar-reset fas fa-arrow-rotate-left"'
  .' rel="tooltip" data-bs-placement="left" data-bs-title="Reset to Defaults"'
  .' data-bs-container="body"></i>';

ajax '/ajax/content/admin/xtchrometask'   => sub { '<div>one row</div>' };
ajax '/ajax/content/admin/jobqueue'       => sub { '<div>one row</div>' };
ajax '/ajax/content/report/xtchromecsv'   => sub { '<div>one row</div>' };
ajax '/ajax/content/report/xtchromenocsv' => sub { '<div>one row</div>' };
ajax '/ajax/content/device/xtchromeprobe' => sub { '<div>one row</div>' };
ajax '/ajax/content/device/unregistered'  => sub { '<div>one row</div>' };

get '/ajax/xt-chrome-device-ports'   => sub { pane_chrome('device', 'ports') };
get '/ajax/xt-chrome-device-netmap'  => sub { pane_chrome('device', 'netmap') };
get '/ajax/xt-chrome-device-details' => sub { pane_chrome('device', 'details') };

subtest 'pane_response__tab_with_a_download__carries_the_csv_link' => sub {
    my $r = pane_response('/ajax/content/admin/xtchrometask?acl_name=core');

    is $r->content,
      '<title>Netdisco</title>'
      .'<a id="nd_csv-download" hx-swap-oob="true"'
      .' href="/ajax/content/admin/xtchrometask?acl_name=core"'
      .' download="netdisco-admin-xtchrometask.csv">'. $CSV_ICON .'</a>'
      .'<div>one row</div>',
      'the link addresses this pane with the query the sidebar submitted';
};

# A pane response is answered once per browser request, but a tenant URL reaches
# it by forward and Dancer runs the after hook again for the response it rebuilds.
# A second copy of an out-of-band element swaps a second time over the first.
subtest 'pane_response__reached_through_a_tenant_prefix__carries_one_csv_link' => sub {
    my $r = pane_response('/t/xt/ajax/content/admin/xtchrometask?acl_name=core');

    my $links = () = $r->content =~ m/id="nd_csv-download"/g;
    is $links, 1, 'one link, not one per pass through the hook';
    like $r->content, qr{href="/t/xt/ajax/content/admin/xtchrometask\?acl_name=core"},
      'and it addresses the tenant, which uri_for is monkeypatched to give';
};

subtest 'pane_response__admin_job_queue__carries_no_csv_link' => sub {
    my $r = pane_response('/ajax/content/admin/jobqueue');

    unlike $r->content, qr/nd_csv-download/,
      'the job queue shell fills that corner with its own controls instead';
};

subtest 'pane_response__report_without_a_download__carries_no_csv_link' => sub {
    my $r = pane_response('/ajax/content/report/xtchromenocsv');

    unlike $r->content, qr/nd_csv-download/,
      'the report shell renders no anchor there, so naming one would miss';
};

subtest 'pane_response__report_with_a_download__carries_the_csv_link' => sub {
    my $r = pane_response('/ajax/content/report/xtchromecsv?age_num=3');

    like $r->content,
      qr{<a id="nd_csv-download" hx-swap-oob="true" href="/ajax/content/report/xtchromecsv\?age_num=3" download="netdisco-report-xtchromecsv\.csv">},
      'a report names its own tag in both the address and the file name';
};

# The device and search shells render the anchor for every tab and hide it on
# the tabs with nothing to download, so those tabs are given a hidden anchor
# rather than no anchor.
subtest 'pane_response__device_tab_without_a_download__hides_the_csv_link' => sub {
    my $r = pane_response('/ajax/content/device/xtchromeprobe?tab=xtchromeprobe');

    like $r->content, qr/<a id="nd_csv-download" hx-swap-oob="true" hidden /,
      'the anchor is replaced with a hidden one, not left showing a stale query';
};

subtest 'pane_response__unregistered_tab__carries_no_chrome' => sub {
    my $r = pane_response('/ajax/content/device/unregistered');

    is $r->content, '<div>one row</div>',
      'nothing registered the tag, so nothing is known about its shell';
};

subtest 'pane_chrome__device_ports__resets_to_the_options_it_was_given' => sub {
    my $r = dancer_response(GET =>
      '/ajax/xt-chrome-device-ports?tab=ports&q=switch1&f=Gi0/1&partial=on');

    like $r->content,
      qr{<a id="nd_sidebar-reset-link" hx-swap-oob="true" href="/device\?tab=ports&amp;reset=on&amp;firstsearch=on&amp;q=switch1&amp;f=Gi0%2F1&amp;partial=on">\Q$RESET_ICON\E</a>},
      'the four fields the Ports sidebar offers, in the order it renders them';
    unlike $r->content, qr/invert/,
      'an unchecked box is not submitted, so it is not carried into the reset';
};

subtest 'pane_chrome__device_netmap__resets_to_the_device_alone' => sub {
    my $r = dancer_response(GET => '/ajax/xt-chrome-device-netmap?tab=netmap&q=switch1');

    like $r->content,
      qr{<a id="nd_sidebar-reset-link" hx-swap-oob="true" href="/device\?tab=netmap&amp;reset=on&amp;firstsearch=on&amp;q=switch1">},
      'the neighbors sidebar has one field to carry';
};

# Those tabs hide the whole sidebar, so the anchor is not on screen to be
# wrong; leaving it alone is what the browser did.
subtest 'pane_chrome__device_tab_with_no_options__carries_no_reset_link' => sub {
    my $r = dancer_response(GET => '/ajax/xt-chrome-device-details?tab=details&q=switch1');

    unlike $r->content, qr/nd_sidebar-reset-link/,
      'only the two tabs with search options have anything to reset to';
};

# htmx drops an out-of-band element the page has no id for without saying so,
# so the runtime half of this is netdisco.js counting what the response offered
# against what htmx placed. This is the half that can be checked without a
# browser: an id renamed on one side and not the other is a miss on every pane
# load.
subtest 'page_shells__every_out_of_band_id__is_rendered_by_the_shell' => sub {
    foreach my $view (qw/device.tt search.tt report.tt admintask.tt/) {
        my $html = read_text("share/views/$view");
        like $html, qr/id="nd_csv-download"/, "$view renders the csv anchor";
    }

    like read_text('share/views/device.tt'), qr/id="nd_sidebar-reset-link"/,
      'and the device shell alone renders the reset anchor';
};

done_testing;
