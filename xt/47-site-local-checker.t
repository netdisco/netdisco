#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use File::Temp ();
use File::Path 'make_path';
use File::Spec::Functions 'catfile';

use App::Netdisco;
use Dancer qw/:moose :script !pass/;

use App::Netdisco::Util::SiteLocal qw/scan_site_local scan_shadowed_files/;

# Build the tree each subtest needs rather than checking fixtures in. Real
# site-local files belong to the sites that wrote them and carry their own
# hostnames and paths, so none is shipped here. Building is also what lets the
# clean case assert against a file with nothing in it to find, which as a
# checked-in fixture would read as an empty file nobody meant to add.
sub site_local_tree {
  my %file_for = @_;
  my $home = File::Temp->newdir();
  foreach my $rel (keys %file_for) {
      my $full = catfile("$home", split m{/}, $rel);
      my ($dir) = $full =~ m{^(.*)/[^/]+$};
      make_path($dir);
      open my $fh, '>', $full or die "$full: $!";
      print {$fh} $file_for{$rel};
      close $fh;
  }
  return $home;
}

subtest 'scan_site_local__file_calls_he_encode__reports_the_datatables_escaper' => sub {
    my $tree = site_local_tree(
      'views/ajax/report/custom.tt' => join("\n",
        '<script type="text/javascript">',
        '  return he.encode(data || "");',
        '</script>',
      ),
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 1, 'one finding'
      or diag explain \@findings;
    is $findings[0]{rule}, 'he-js', 'attributed to the he.js removal';
    is $findings[0]{line}, 2, 'at the line that calls it';
    is $findings[0]{release}, '2.105002', 'naming the release that removed it';
    like $findings[0]{advice}, qr/DataTable\.util\.escapeHtml/,
      'and giving the replacement by name';
};

subtest 'scan_site_local__file_uses_no_removed_api__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/ajax/report/custom.tt' => join("\n",
        '<script type="text/javascript">',
        '  return DataTable.util.escapeHtml(data || "");',
        '</script>',
      ),
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'a migrated file is silent';
};

subtest 'scan_site_local__file_calls_history_js__reports_the_native_api' => sub {
    my $tree = site_local_tree(
      'views/js/custom.js' => join("\n",
        'if (window.History && History.enabled) {',
        '  History.pushState({tab: t}, null, url);',
        '}',
      ),
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 2, 'both lines are reported'
      or diag explain \@findings;
    is_deeply [ map { $_->{line} } @findings ], [1, 2],
      'in file order';
    is $findings[0]{rule}, 'history-js', 'attributed to the history.js removal';
    like $findings[0]{advice}, qr/HX-Push-Url/,
      'and naming the response header that replaces it';
};

# The browser's own history object survived the removal, so a file that calls
# it must not be reported. This is the assertion that makes the rule's
# case-sensitivity load-bearing rather than incidental. netdisco itself no
# longer touches history, but a site that does is not broken by that, so this
# also pins the history-replay rule to netdisco's own removed names.
subtest 'scan_site_local__file_uses_the_native_history__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/js/custom.js' => join("\n",
        'history.pushState({tab: t}, "", url);',
        'window.addEventListener("popstate", replay);',
      ),
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'lowercase history is the replacement, not a finding';
};

subtest 'scan_site_local__column_asks_for_the_natural_sort__reports_it' => sub {
    my $tree = site_local_tree(
      'views/ajax/report/custom.tt' => join("\n",
        '{ "data": "name", "type": "natural" },',
        '{ "data": "port", "sType": "natural" },',
        '  "aoColumns": [ { "sSortDataType": "natural-asc" } ]',
      ),
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 3, 'every spelling is caught'
      or diag explain \@findings;
    is_deeply [ map { $_->{rule} } @findings ],
      [ ('natural-js') x 3 ], 'all attributed to natural.js';
    is $findings[0]{release}, '2.105004', 'naming the release that removed it';
};

subtest 'scan_site_local__handler_calls_do_search__reports_the_htmx_attributes' => sub {
    my $tree = site_local_tree(
      'views/js/common.js' => join("\n",
        "\$('#ports_form').submit(function (event) {",
        "  do_search(event, 'ports');",
        '});',
      ),
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 1, 'one finding'
      or diag explain \@findings;
    is $findings[0]{rule}, 'do-search', 'attributed to the do_search removal';
    is $findings[0]{line}, 2, 'at the line that calls it';
    like $findings[0]{advice}, qr/hx-get/,
      'and pointing at the attributes that replace it';
};

subtest 'scan_site_local__fragment_includes_datatabledefaults__reports_the_removal' => sub {
    my $tree = site_local_tree(
      'views/ajax/report/custom.tt' => join("\n",
        '<table data-nd-table=\'{}\'>',
        "[% INCLUDE 'ajax/datatabledefaults.tt' %]",
      ),
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 1, 'one finding'
      or diag explain \@findings;
    is $findings[0]{rule}, 'datatabledefaults-include',
      'attributed to the removed fragment';
    like $findings[0]{advice}, qr/data-nd-table/,
      'and pointing at its replacement';
};

subtest 'scan_site_local__fragment_moved_its_options_into_data_nd_table__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/ajax/report/custom.tt' =>
        q{<table data-nd-table='{"columns":[{"data":"ip","render":"escape"}]}'></table>},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'a migrated fragment is silent';
};

subtest 'scan_site_local__template_reads_has_sidebar__reports_the_removed_global' => sub {
    my $tree = site_local_tree(
      'views/sidebar/report/custom.tt' =>
        q{[% IF has_sidebar['custom'] %]shown[% END %]},
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 1, 'one finding'
      or diag explain \@findings;
    is $findings[0]{rule}, 'has-sidebar-global', 'attributed to the removed global';
    like $findings[0]{advice}, qr/data-nd-has-sidebar/,
      'and naming its replacement';
};

subtest 'scan_site_local__template_uses_the_hidden_input_marker__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/sidebar/report/custom.tt' =>
        q{<input type="hidden" data-nd-has-sidebar="custom" value="0">},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'a migrated sidebar marker is silent';
};

subtest 'scan_site_local__page_template_includes_a_js_page_script__reports_the_removal' => sub {
    my $tree = site_local_tree(
      'views/device.tt' => "[% INCLUDE 'js/device.js' %]",
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 1, 'one finding'
      or diag explain \@findings;
    is $findings[0]{rule}, 'page-script-include',
      'attributed to the removed page scripts';
    like $findings[0]{advice}, qr/netdisco\.js/,
      'and naming where the scripts live now';
};

subtest 'scan_site_local__page_template_includes_no_script__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/device.tt' => qq{<form id="ports_form" hx-get="/ajax/content/device/ports">\n</form>\n},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'a page template carrying no script include is silent';
};

subtest 'scan_site_local__layout_names_the_old_portcontrol_file__reports_the_rename' => sub {
    my $tree = site_local_tree(
      'views/layouts/main.tt' =>
        q{<script src="/javascripts/netdisco_portcontrol.js"></script>},
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 1, 'one finding'
      or diag explain \@findings;
    is $findings[0]{rule}, 'portcontrol-js-renamed', 'attributed to the rename';
    like $findings[0]{advice}, qr/netdisco-portcontrol\.js/,
      'and naming the current file';
};

subtest 'scan_site_local__layout_names_the_current_portcontrol_file__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/layouts/main.tt' =>
        q{<script src="/javascripts/netdisco-portcontrol.js"></script>},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'a layout naming the current file is silent';
};

subtest 'scan_site_local__handler_calls_nd_submit__reports_the_htmx_trigger' => sub {
    my $tree = site_local_tree(
      'views/js/custom.js' => "nd_submit('#ports_form');\n",
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 1, 'one finding'
      or diag explain \@findings;
    is $findings[0]{rule}, 'nd-submit', 'attributed to the removed helper';
    like $findings[0]{advice}, qr/htmx\.trigger/,
      'and naming what submits the form now';
};

subtest 'scan_site_local__handler_triggers_the_form_itself__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/js/custom.js' => "htmx.trigger('#ports_form', 'submit');\n",
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'the shipped replacement is silent';
};

subtest 'scan_site_local__file_sets_the_page_title__reports_every_spelling' => sub {
    my $tree = site_local_tree(
      'views/js/custom.js' => join("\n",
        'document.title = update_page_title(tab);',
        'var fallback = default_pgtitle;',
        'var branding = document.body.dataset.ndTitle;',
      ),
      'views/layouts/main.tt' =>
        q{<body data-nd-title="[% settings.branding_text %]">},
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 4, 'the two globals, the dataset read and the attribute'
      or diag explain \@findings;
    is_deeply [ map { $_->{rule} } @findings ],
      [ ('page-title-globals') x 4 ], 'all one removal';
    like $findings[0]{advice}, qr/<title>/,
      'advice names where the title comes from now';
};

subtest 'scan_site_local__fragment_carries_its_own_title__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/ajax/report/custom.tt' => "<title>Netdisco - Custom</title>\n",
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'a fragment titling itself is what this release asks for';
};

subtest 'scan_site_local__file_replays_the_history__reports_the_response_headers' => sub {
    my $tree = site_local_tree(
      'views/js/custom.js' => join("\n",
        'if (is_from_state_event == 0) {',
        "  update_browser_history(tab, '1');",
        '}',
      ),
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 2, 'the flag and the call'
      or diag explain \@findings;
    is_deeply [ map { $_->{rule} } @findings ],
      [ ('history-replay') x 2 ], 'both attributed to the replay removal';
    like $findings[1]{advice}, qr/HX-Replace-Url/,
      'and naming the headers that carry the address now';
};

subtest 'scan_site_local__file_uses_jquery_deserialize__reports_the_removal' => sub {
    my $tree = site_local_tree(
      'views/layouts/main.tt' =>
        q{<script src="/javascripts/jquery-deserialize.js"></script>},
      'views/js/custom.js' => "\$('#ports_form').deserialize(state.fields);\n",
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 2, 'the script tag and the call'
      or diag explain \@findings;
    is_deeply [ map { $_->{rule} } @findings ],
      [ ('jquery-deserialize') x 2 ], 'both attributed to the removed plug-in';
};

# serialize() is jQuery's own and is called all over netdisco, so a rule that
# caught it would report every form handler a site has ever written.
subtest 'scan_site_local__file_calls_jquery_serialize__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/js/custom.js' => join("\n",
        "var query = \$('#ports_form').serialize();",
        "var fields = \$('#ports_form').serializeArray();",
      ),
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'the plug-in that went is deserialize, not serialize';
};

subtest 'scan_site_local__file_rebuilds_the_csv_link__reports_the_oob_anchor' => sub {
    my $tree = site_local_tree(
      'views/js/custom.js' => "update_csv_download_link(page, tab, '1');\n",
      'views/device.tt' => qq{<form data-nd-tab="ports" data-nd-csv="1">\n</form>\n},
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 2, 'the rewriter and the attribute that fed it'
      or diag explain \@findings;
    is_deeply [ map { $_->{rule} } @findings ],
      [ ('csv-download-link') x 2 ], 'both attributed to one removal';
    like $findings[0]{advice}, qr/nd_csv-download/,
      'advice names the id the response now swaps into';
};

subtest 'scan_site_local__page_template_keeps_only_the_tab_marker__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/device.tt' => qq{<form data-nd-tab="ports" hx-get="/ajax/content/device/ports">\n</form>\n},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'data-nd-tab stayed, so only data-nd-csv is a finding';
};

subtest 'scan_site_local__file_aborts_a_tab_form__reports_the_sync_attribute' => sub {
    my $tree = site_local_tree(
      'views/js/custom.js' => "htmx.trigger(leaving, 'htmx:abort');\n",
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 1, 'one finding'
      or diag explain \@findings;
    is $findings[0]{rule}, 'htmx-abort-trigger',
      'attributed to the hand-written cancellation';
    like $findings[0]{advice}, qr/hx-sync/,
      'and naming the attribute that cancels for it now';
};

# The vendored htmx bundle listens for this event, so a rule keyed on the bare
# event name told any site keeping its own copy of that file to change the
# library. The rule is anchored on the trigger instead.
subtest 'scan_site_local__a_copy_of_the_htmx_library__is_not_reported' => sub {
    my $tree = site_local_tree(
      'javascripts/htmx.min.js' =>
        qq{e.addEventListener("htmx:abort",r),t.listeners.push(r)\n},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'listening for the event is what the library does, not what a site must fix';
};

subtest 'scan_site_local__form_declares_hx_sync__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/device.tt' =>
        qq{<form data-nd-tab="ports" hx-sync="closest .nd_sidebar:replace">\n</form>\n},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'the declared cancellation is the replacement, not a finding';
};

subtest 'scan_site_local__layout_names_the_old_datatables_file__reports_the_rename' => sub {
    my $tree = site_local_tree(
      'views/layouts/main.tt' =>
        q{<script src="/javascripts/jquery.dataTables.min.js"></script>},
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 1, 'one finding'
      or diag explain \@findings;
    is $findings[0]{rule}, 'datatables-js-renamed', 'attributed to the rename';
    is $findings[0]{release}, '2.109000', 'naming the release that renamed it';
    like $findings[0]{advice}, qr/renamed dataTables\.min\.js/,
      'and naming the current file';
};

# The new name is the old one with the prefix taken off, so a rule written
# without the prefix would report every layout including the shipped one.
subtest 'scan_site_local__layout_names_the_current_datatables_file__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/layouts/main.tt' =>
        q{<script src="/javascripts/dataTables.min.js"></script>},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'a layout naming the current file is silent';
};

subtest 'scan_site_local__file_uses_floatthead__reports_the_sticky_header' => sub {
    my $tree = site_local_tree(
      'views/layouts/main.tt' =>
        q{<script src="/javascripts/jquery.floatThead.js"></script>},
      'views/js/custom.js' => "\$('table.nd_floatinghead').floatThead('reflow');\n",
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 2, 'the script tag and the call'
      or diag explain \@findings;
    is_deeply [ map { $_->{rule} } @findings ],
      [ ('floatthead-js') x 2 ], 'both attributed to the removed plug-in';
    like $findings[1]{advice}, qr/nd_floatinghead/,
      'advice names the class the stylesheet keys the sticky header on';
};

subtest 'scan_site_local__table_carries_the_sticky_class__reports_nothing' => sub {
    my $tree = site_local_tree(
      'views/ajax/admintask/custom.tt' =>
        q{<table class="table table-bordered nd_floatinghead">},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'the class the stylesheet sticks is the replacement, not a finding';
};

subtest 'scan_site_local__several_files_and_rules__sorts_by_path_then_line' => sub {
    my $tree = site_local_tree(
      'views/b.tt' => "he.encode(x);\n",
      'views/a.tt' => join("\n", 'History.getState();', 'he.decode(y);'),
    );

    my @findings = scan_site_local({ paths => ["$tree"] });

    is scalar @findings, 3, 'every match across both files';
    my @order = map { ($_->{path} =~ m{([^/]+)$})[0] . ':' . $_->{line} }
                @findings;
    is_deeply \@order, ['a.tt:1', 'a.tt:2', 'b.tt:1'],
      'sorted by path then line, so the report reads as a file list';
};

subtest 'scan_site_local__rules_restricted_to_one__applies_only_that_rule' => sub {
    my $tree = site_local_tree(
      'views/a.tt' => join("\n", 'History.getState();', 'he.decode(y);'),
    );

    my @findings =
      scan_site_local({ paths => ["$tree"], rules => ['he-js'] });

    is scalar @findings, 1, 'only the named rule ran';
    is $findings[0]{rule}, 'he-js', 'and it is the one asked for';
};

subtest 'scan_site_local__path_does_not_exist__returns_nothing_and_lives' => sub {
    my @findings =
      scan_site_local({ paths => ['/nonexistent/nd-site-local/share/views'] });

    is_deeply \@findings, [],
      'a configured path an install never created is not fatal';
};

# The rule table is the thing a later rung edits, so its shape is asserted here
# rather than left to the scan tests to imply.
subtest 'site_local_rules__called__describes_every_rule_the_scan_applies' => sub {
    my @rules = App::Netdisco::Util::SiteLocal::site_local_rules();

    is scalar @rules, 24, 'twenty-four rules ship in this release';
    is_deeply [ sort map { $_->{name} } @rules ],
      [ 'csv-download-link', 'csv-download-target',
        'datatabledefaults-include', 'datatables-js-renamed', 'do-search',
        'floatthead-js', 'has-sidebar-global', 'he-js', 'history-js',
        'history-replay', 'htmx-abort-trigger', 'jquery-deserialize',
        'jquery-ui-autocomplete', 'jquery-ui-removed', 'jstree-removed',
        'layout-shadow', 'natural-js', 'nd-submit', 'page-script-include',
        'page-title-globals', 'portcontrol-js-renamed', 'sidebar-reset-target',
        'tab-page-shadow', 'tab-sync-attribute' ],
      'named as the report cites them, file rules included';
    ok !(grep { !length($_->{advice} || '') } @rules),
      'and every rule carries remediation advice';
};

# The paths come from settings rather than from the caller, so the action and
# the web application's startup check cannot drift apart. site_local_files is off by default,
# and when it is off the nd-site-local directories are not scanned even if they
# exist, because the app is not reading them either.
# Two of the file rules below are warned about at startup, so a false positive
# is noise on every worker boot at every site. Hence the clean cases alongside
# each.
#
# Several file rules read the same shipped page templates, so a subtest about
# one of them names it: a fixture written to trip one is otherwise missing what
# the others require, and the count would then report the fixture rather than
# the rule.

subtest 'scan_shadowed_files__tab_page_copy_without_hx_get__reports_the_empty_pane' => sub {
    my $tree = site_local_tree(
      'device.tt' => qq{<form id="ports_form" method="get" action="/device">\n</form>\n});

    my @findings = scan_shadowed_files(
      { paths => ["$tree"], rules => ['tab-page-shadow'] });

    is scalar @findings, 1, 'one finding for the shadowed tab page';
    is $findings[0]{rule}, 'tab-page-shadow', 'named the rule';
    is $findings[0]{kind}, 'file', 'reported as a file rule, so it carries no line';
    ok !exists $findings[0]{line}, 'and really has no line to cite';
    like $findings[0]{advice}, qr/hx-get/, 'advice names the attribute to add';
};

subtest 'scan_shadowed_files__tab_page_copy_carrying_hx_get__reports_nothing' => sub {
    my $tree = site_local_tree(
      'device.tt' => qq{<form id="ports_form" hx-get="/ajax/content/device/ports">\n</form>\n});

    is scalar scan_shadowed_files(
      { paths => ["$tree"], rules => ['tab-page-shadow'] }), 0,
      'a copy that adopted the transport is not a finding';
};

subtest 'scan_shadowed_files__no_tab_page_shadowed__reports_nothing' => sub {
    my $tree = site_local_tree('ajax/report/custom.tt' => qq{<div>hi</div>\n});

    is scalar scan_shadowed_files({ paths => ["$tree"] }), 0,
      'silence is the normal case, and this runs at every worker startup';
};

subtest 'scan_shadowed_files__layout_copy_without_uri_base__reports_the_dead_layout' => sub {
    my $tree = site_local_tree(
      'layouts/main.tt' => qq{<body>\n<script src="/javascripts/netdisco.js"></script>\n</body>\n});

    my @findings = scan_shadowed_files({ paths => ["$tree"] });

    is scalar @findings, 1, 'one finding for the shadowed layout';
    is $findings[0]{rule}, 'layout-shadow', 'named the rule';
    is $findings[0]{kind}, 'file', 'reported as a file rule, so it carries no line';
    ok !exists $findings[0]{line}, 'and really has no line to cite';
    like $findings[0]{advice}, qr/data-nd-uri-base/,
      'advice names the missing attribute';
};

subtest 'scan_shadowed_files__layout_copy_carrying_uri_base__reports_nothing' => sub {
    my $tree = site_local_tree(
      'layouts/main.tt' => qq{<body data-nd-uri-base="">\n</body>\n});

    is scalar scan_shadowed_files({ paths => ["$tree"] }), 0,
      'a copy that adopted the body attributes is not a finding';
};

subtest 'scan_shadowed_files__every_tab_page__is_checked' => sub {
    my $tree = site_local_tree(
      map {; $_ => qq{<form method="get">\n</form>\n} } qw/device.tt search.tt report.tt/);

    my @findings = scan_shadowed_files(
      { paths => ["$tree"], rules => ['tab-page-shadow'] });

    is scalar @findings, 3, 'device, search and report are all tab pages';
    is_deeply [map {; $_->{path} =~ m{([^/]+)$}; $1 } @findings],
      [qw/device.tt report.tt search.tt/], 'sorted by path';
};

subtest 'scan_shadowed_files__page_copy_without_the_csv_id__reports_the_lost_link' => sub {
    my $tree = site_local_tree(
      'search.tt' => qq{<span id="nd_search-name">Search</span>\n});

    my @findings = scan_shadowed_files(
      { paths => ["$tree"], rules => ['csv-download-target'] });

    is scalar @findings, 1, 'one finding for the missing target';
    is $findings[0]{rule}, 'csv-download-target', 'named the rule';
    like $findings[0]{advice}, qr/nd_csv-download/, 'advice names the id to restore';
};

subtest 'scan_shadowed_files__page_copy_keeping_the_csv_id__reports_nothing' => sub {
    my $tree = site_local_tree(
      'search.tt' => qq{<a id="nd_csv-download" href="#" download="netdisco.csv"></a>\n});

    is scalar scan_shadowed_files(
      { paths => ["$tree"], rules => ['csv-download-target'] }), 0,
      'the anchor the response swaps into is there';
};

subtest 'scan_shadowed_files__device_copy_without_the_reset_id__reports_the_lost_link' => sub {
    my $tree = site_local_tree(
      'device.tt' => qq{<div class="nd_sidebar"></div>\n});

    my @findings = scan_shadowed_files(
      { paths => ["$tree"], rules => ['sidebar-reset-target'] });

    is scalar @findings, 1, 'one finding for the missing target';
    is $findings[0]{rule}, 'sidebar-reset-target', 'named the rule';
    like $findings[0]{advice}, qr/nd_sidebar-reset-link/,
      'advice names the id to restore';
};

subtest 'scan_shadowed_files__device_copy_keeping_the_reset_id__reports_nothing' => sub {
    my $tree = site_local_tree(
      'device.tt' => qq{<a id="nd_sidebar-reset-link" href="#"></a>\n});

    is scalar scan_shadowed_files(
      { paths => ["$tree"], rules => ['sidebar-reset-target'] }), 0,
      'the anchor the response swaps into is there';
};

# only device.tt carries a reset link, so a search or report copy without one is
# correct rather than stale
subtest 'scan_shadowed_files__search_copy_without_the_reset_id__reports_nothing' => sub {
    my $tree = site_local_tree(
      'search.tt' => qq{<div class="nd_sidebar"></div>\n});

    is scalar scan_shadowed_files(
      { paths => ["$tree"], rules => ['sidebar-reset-target'] }), 0,
      'the reset link belongs to the device page alone';
};

subtest 'scan_shadowed_files__page_copy_without_hx_sync__reports_the_uncancelled_request' => sub {
    my $tree = site_local_tree(
      'report.tt' => qq{<form hx-get="/ajax/content/report/portlog">\n</form>\n});

    my @findings = scan_shadowed_files(
      { paths => ["$tree"], rules => ['tab-sync-attribute'] });

    is scalar @findings, 1, 'one finding for the missing attribute';
    is $findings[0]{rule}, 'tab-sync-attribute', 'named the rule';
    like $findings[0]{advice}, qr/nd_sidebar:replace/,
      'advice gives the attribute value to add';
};

subtest 'scan_shadowed_files__page_copy_carrying_hx_sync__reports_nothing' => sub {
    my $tree = site_local_tree(
      'report.tt' => qq{<form hx-get="/x" hx-sync="closest .nd_sidebar:replace">\n</form>\n});

    is scalar scan_shadowed_files(
      { paths => ["$tree"], rules => ['tab-sync-attribute'] }), 0,
      'a copy that adopted the cancellation is not a finding';
};

# The web application runs this at every worker boot and a site cannot turn the
# warning off, so only a rule whose failure nothing else reports belongs in it:
# a pane that renders empty and says nothing, and a layout that kills every
# page. The rest reach the person through the console, a stale link or a
# lingering indicator, and wait for the report they asked for.
subtest 'scan_shadowed_files__startup_only__reports_the_two_silent_failures' => sub {
    my $tree = site_local_tree(
      'device.tt' => qq{<form method="get">\n</form>\n},
      'layouts/main.tt' => qq{<body>\n</body>\n});

    my @startup = scan_shadowed_files({ paths => ["$tree"], startup => 1 });

    is_deeply [ map { $_->{rule} } @startup ],
      [ 'tab-page-shadow', 'layout-shadow' ],
      'the empty pane and the dead layout, and nothing else';

    my @all = scan_shadowed_files({ paths => ["$tree"] });
    ok scalar @all > scalar @startup,
      'the rest are still reported to whoever ran checksitelocal';
};

subtest 'site_local_paths__site_local_files_off__returns_only_template_paths' => sub {
    my $home = File::Temp->newdir();
    local $ENV{NETDISCO_HOME} = "$home";
    config->{'template_paths'} = ['/etc/netdisco/views'];
    config->{'site_local_files'} = 0;

    is_deeply [ App::Netdisco::Util::SiteLocal::site_local_paths() ],
      ['/etc/netdisco/views'],
      'nd-site-local is not scanned when the app is not reading it';
};

subtest 'site_local_paths__site_local_files_on__adds_the_nd_site_local_dirs' => sub {
    my $home = File::Temp->newdir();
    local $ENV{NETDISCO_HOME} = "$home";
    config->{'template_paths'} = [];
    config->{'site_local_files'} = 1;

    my @paths = App::Netdisco::Util::SiteLocal::site_local_paths();

    is scalar @paths, 2, 'both directories Web.pm adds';
    like $paths[0], qr{nd-site-local/share$},
      'the share directory';
    like $paths[1], qr{nd-site-local/share/views$},
      'and the views directory below it';
};

# site_local_paths returns nd-site-local/share AND nd-site-local/share/views,
# because Web.pm adds both, and the second is inside the first. Every file below
# views is therefore reached twice, and a report that lists each finding twice
# reads as twice as much breakage as exists.
subtest 'scan_site_local__paths_overlap__reports_each_finding_once' => sub {
    my $tree = site_local_tree(
      'share/views/custom.tt' => "he.encode(x);\n",
    );

    my @findings = scan_site_local({ paths =>
      [ "$tree/share", "$tree/share/views" ] });

    is scalar @findings, 1,
      'the nested path does not double the finding'
      or diag explain \@findings;
};

# A bare `sort` as the last statement of a sub returns undef in scalar context
# rather than a count, so a caller writing `my $n = scan_site_local(...)` gets
# undef and a report of zero. The contract is a list; this pins the scalar case
# so the natural mistake cannot be made silently.
subtest 'scan_site_local__called_in_scalar_context__returns_the_count' => sub {
    my $tree = site_local_tree(
      'views/a.tt' => join("\n", 'History.getState();', 'he.decode(y);'),
    );

    my $count = scan_site_local({ paths => ["$tree"] });

    is $count, 2, 'scalar context gives the number of findings';
};

subtest 'scan_site_local__file_calls_jquery_ui_autocomplete__reports_the_attributes' => sub {
    my $tree = site_local_tree(
      'views/ajax/report/custom.tt' => join("\n",
        '<script type="text/javascript">',
        "  \$('#mybox').autocomplete({ source: '/ajax/data/deviceip/typeahead' });",
        '</script>'),
    );

    my @found = scan_site_local({ paths => ["$tree"] });
    is scalar @found, 1, 'one finding';
    is $found[0]->{rule}, 'jquery-ui-autocomplete', 'the autocomplete rule matched';
    like $found[0]->{advice}, qr/data-nd-typeahead/,
      'the advice names the attribute that replaces the call';
};

# Both the minified library and its stylesheet carry the class the widget adds,
# so a rule keyed on that class told any site keeping its own copy to change the
# library. The rule is anchored on the call instead.
subtest 'scan_site_local__a_copy_of_the_jquery_ui_library__is_not_reported' => sub {
    my $tree = site_local_tree(
      'javascripts/jquery-ui.min.js' =>
        qq{t.widget("ui.autocomplete",{version:"1.14.2",defaultElement:"<input>"})\n},
      'css/smoothness/jquery-ui.min.css' =>
        qq{.ui-autocomplete{position:absolute;top:0;left:0;cursor:default}\n},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'carrying the widget is what the library does, not what a site must fix';
};

subtest 'scan_site_local__layout_copy_loads_jquery_ui__reports_the_removal' => sub {
    my $tree = site_local_tree(
      'views/layouts/main.tt' =>
        '<script src="[% uri_base %]/javascripts/jquery-ui.min.js"></script>',
    );

    my @found = scan_site_local({ paths => ["$tree"] });
    is scalar @found, 1, 'one finding';
    is $found[0]->{rule}, 'jquery-ui-removed', 'the library rule matched';
};

# The stylesheet is a separate line in a copied layout, and a copy that keeps
# it gets a 404 rather than an error, so nothing else would report it.
subtest 'scan_site_local__layout_copy_links_the_smoothness_theme__reports_the_removal' => sub {
    my $tree = site_local_tree(
      'views/layouts/main.tt' =>
        '<link rel="stylesheet" href="[% uri_base %]/css/smoothness/jquery-ui.min.css"/>',
    );

    my @found = scan_site_local({ paths => ["$tree"] });
    is scalar @found, 1, 'one finding';
    is $found[0]->{rule}, 'jquery-ui-removed', 'the library rule matched';
};

subtest 'scan_site_local__handler_selects_the_jstree_container__reports_the_replacement' => sub {
    my $tree = site_local_tree(
      'javascripts/mypane.js' => qq{\$("#jstree").jstree("search", "x");\n},
    );

    my @found = scan_site_local({ paths => ["$tree"] });
    is scalar @found, 1, 'one finding';
    is $found[0]->{rule}, 'jstree-removed', 'a copy of the old pane script is reported';
};

subtest 'scan_site_local__template_names_the_jstree_container__reports_the_replacement' => sub {
    my $tree = site_local_tree(
      'views/ajax/device/snmp.tt' =>
        '<div id="jstree" class="nd_scrollable" data-nd-device="[% device %]"></div>',
    );

    my @found = scan_site_local({ paths => ["$tree"] });
    is scalar @found, 1, 'one finding';
    is $found[0]->{rule}, 'jstree-removed', 'the jstree rule matched';
    like $found[0]->{advice}, qr/nd_snmp-tree/,
      'the advice names what replaces the container';
};

# Anchored on the container and the call rather than the bare name, so a site
# keeping its own copy of the library is not told to change the library. The
# same false positive was measured on the htmx and jQuery UI rules.
subtest 'scan_site_local__a_copy_of_the_jstree_library__is_not_reported' => sub {
    # named outside the vendored directory, because the path itself is one of
    # the things the rule looks for in a copied layout
    my $tree = site_local_tree(
      'javascripts/vendor-tree.js' =>
        qq{e.jstree.plugins.search=function(e,t){this.bind=function(){}}\n},
    );

    is_deeply [ scan_site_local({ paths => ["$tree"] }) ], [],
      'carrying the plugin is what the library does, not what a site must fix';
};

done_testing;
