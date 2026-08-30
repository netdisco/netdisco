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

done_testing;
