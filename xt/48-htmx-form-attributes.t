#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot 'render_template';

# The sidebar forms load their panes over htmx, so each needs five attributes.
# Losing hx-headers is the dangerous one and the silent one: without the header
# the request is not an XHR, Dancer's route_cache stores the catch-all the path
# fell through to, and every later request for that path 404s for the rest of
# that worker's life. Nothing in the response says so.
#
# hx-sync is the second of that kind. It names the shared element that owns the
# in-flight request, so entering a tab aborts the one the leaving tab started.
# It is repeated on every form rather than set once on the sidebar they share,
# because htmx 4 ends implicit attribute inheritance and an inherited one would
# have to be rewritten with an :inherited suffix; a miss there stops the abort
# with nothing in the console. The selector must resolve, so the .nd_sidebar
# ancestor is checked beside it: htmx throws on an unresolvable sync element.
#
# The snapshots cannot hold this. They render with empty tab lists, so the
# FOREACH bodies that build these forms never run, and device.tt.html and
# search.tt.html carry no form at all. They also leave uri_for unstubbed, so
# every route in a snapshot is blank; supplying it below is what lets this
# check the route each form posts at.

my @PAGES = (
  { view => 'device.tt', key => '_device_tabs', kind => 'device' },
  { view => 'search.tt', key => '_search_tabs', kind => 'search' },
);

# render_if gates device.tt's pane loop, so without it the forms render and the
# panes and indicators they point at do not.
my @TABS = map {; +{ tag => $_, render_if => 1 } } qw/ports netmap vlan/;

foreach my $page (@PAGES) {
    subtest "$page->{view}__every_tab_form__carries_the_htmx_attributes" => sub {
        my ($html, $error) = render_template($page->{view},
          { uri_for => sub { $_[0] },
            settings => { $page->{key} => \@TABS } });
        is $error, undef, 'renders' or return;

        foreach my $tab (@TABS) {
            my $tag = $tab->{tag};
            my ($form) = $html =~ m{(<form id="${tag}_form".*?>)}s;
            ok $form, "$tag has a form" or next;

            like $form, qr{hx-get="[^"]*/ajax/content/$page->{kind}/$tag"},
              "$tag posts at its own content route";
            like $form, qr{hx-target="#${tag}_pane"}, "$tag targets its own pane";
            like $form, qr{hx-headers=.*X-Requested-With}, "$tag sends the XHR header";
            like $form, qr{hx-indicator="#${tag}_indicator"}, "$tag names its indicator";
            like $html, qr{id="${tag}_indicator"}, "$tag has that indicator";
            like $form, qr{hx-sync="closest \.nd_sidebar:replace"},
              "$tag hands its in-flight request to the shared sidebar";
            like $html, qr{class="nd_sidebar[ "]}, "$tag can resolve that sidebar";
        }
    };
}

subtest 'report_tt__the_single_form__carries_the_htmx_attributes' => sub {
    my ($html, $error) = render_template('report.tt',
      { uri_for => sub { $_[0] }, report => { tag => 'nodevendor' } });
    is $error, undef, 'renders' or return;

    my ($form) = $html =~ m{(<form id="nodevendor_form".*?>)}s;
    ok $form, 'the report form is there' or return;

    like $form, qr{hx-get="[^"]*/ajax/content/report/nodevendor"},
      'posts at its own content route';
    like $form, qr{hx-target="#nodevendor_pane"}, 'targets its own pane';
    like $form, qr{hx-headers=.*X-Requested-With}, 'sends the XHR header';
    like $form, qr{hx-indicator="#nodevendor_indicator"}, 'names its indicator';
    like $html, qr{id="nodevendor_indicator"}, 'and has that indicator';
    like $form, qr{hx-sync="closest \.nd_sidebar:replace"},
      'hands its in-flight request to the sidebar';
    like $html, qr{class="nd_sidebar[ "]}, 'and can resolve that sidebar';
};

# admintask.tt renders one form like report.tt does, but from its own template
# and its own variables, so the same attributes are a separate check. The tag
# is deliberately not jobqueue: that one tab drops hx-indicator on purpose,
# because its timer re-submits the form every few seconds.
subtest 'admintask_tt__the_single_form__carries_the_htmx_attributes' => sub {
    my ($html, $error) = render_template('admintask.tt',
      { uri_for => sub { $_[0] }, task => { tag => 'topology' } });
    is $error, undef, 'renders' or return;

    my ($form) = $html =~ m{(<form id="topology_form".*?>)}s;
    ok $form, 'the admin task form is there' or return;

    like $form, qr{hx-get="[^"]*/ajax/content/admin/topology"},
      'posts at its own content route';
    like $form, qr{hx-target="#topology_pane"}, 'targets its own pane';
    like $form, qr{hx-headers=.*X-Requested-With}, 'sends the XHR header';
    like $form, qr{hx-indicator="#topology_indicator"}, 'names its indicator';
    like $html, qr{id="topology_indicator"}, 'and has that indicator';
    like $form, qr{hx-sync="closest \.nd_sidebar:replace"},
      'hands its in-flight request to the sidebar';
    like $html, qr{class="nd_sidebar[ "]}, 'and can resolve that sidebar';
};

done_testing;
