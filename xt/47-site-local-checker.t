#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use File::Temp ();
use File::Path 'make_path';
use File::Spec::Functions 'catfile';

use App::Netdisco::Util::SiteLocal 'scan_site_local';

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
    like $findings[0]{advice}, qr/history\.pushState/,
      'and naming the native replacement';
};

# The browser's own history object survived the removal, so a file that already
# uses it must not be reported. This is the assertion that makes the rule's
# case-sensitivity load-bearing rather than incidental.
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

    is scalar @rules, 3, 'three rules ship in this release';
    is_deeply [ sort map { $_->{name} } @rules ],
      [ 'he-js', 'history-js', 'natural-js' ], 'named as the report cites them';
    ok !(grep { !length($_->{advice} || '') } @rules),
      'and every rule carries remediation advice';
};

done_testing;
