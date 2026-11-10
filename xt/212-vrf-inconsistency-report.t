#!/usr/bin/env perl

use strict;
use warnings;

# The VRF Naming Inconsistencies report is a UNION ALL of four findings, one
# branch each, and none may list the default table (vrf = ''). CI has no
# database, so the SQL is checked as text and the templates are rendered with
# fixed rows. Ordering lives in the route, not the view, because DBIC wraps a
# virtual view in a subselect.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use Dancer ':syntax';
use App::Netdisco::Web::Plugin::Report::VrfInconsistency;
use App::Netdisco::DB::Result::Virtual::VrfInconsistency;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template/;

sub slurp {
  my $file = shift;
  open my $fh, '<', $file or die "$file: $!";
  local $/;
  return scalar <$fh>;
}

my $sql = (slurp('lib/App/Netdisco/DB/Result/Virtual/VrfInconsistency.pm')
  =~ /<<'ENDSQL'\);\n(.*?)\nENDSQL/s)[0] // '';
my @branches = split /\bUNION ALL\b/, $sql;

subtest 'report__registered__in_ip_category' => sub {
  my $report = setting('_reports')->{vrfinconsistency};
  ok $report, 'registered under its tag';
  is $report->{category}, 'IP', 'IP category';
  is $report->{label}, 'VRF Naming Inconsistencies', 'label';
  ok $report->{provides_csv}, 'provides CSV';
  ok $report->{api_endpoint}, 'API endpoint';
  ok scalar(grep { $_ eq 'Report::VrfInconsistency' }
    @{ YAML::XS::LoadFile('share/config.yml')->{web_plugins} }), 'enabled in web_plugins';
};

subtest 'virtual__sql__four_findings_union' => sub {
  ok $sql, 'view definition found';
  is scalar(@branches), 4, 'four UNION ALL branches';
  my @found = map { /'(different names|similar names|linked, one subnet|shared RD)'\s+AS finding/ ? $1 : '' } @branches;
  is_deeply [sort @found], ['different names', 'linked, one subnet', 'shared RD', 'similar names'],
    'one branch per finding';
  foreach my $branch (@branches) {
    like $branch, qr/vrf\s*<>\s*''/, 'branch excludes the default table';
  }
};

# a vrf_domains entry (and its join) groups differently named VRFs on purpose,
# so a manual domain listed here on every load buried the real findings
subtest 'virtual__different_names__manual_domains_excluded' => sub {
  my ($branch) = grep { /'different names'/ } @branches;
  like $branch, qr/AND \(d\.inferred_name IS NULL OR d\.inferred_name NOT LIKE 'manual:%'\)/,
    'manual domains left out';
};

subtest 'virtual__similar_names__same_domain_excluded' => sub {
  my ($branch) = grep { /'similar names'/ } @branches;
  like $branch, qr/count\(DISTINCT\s+\w+\.domain_id\)\s*>\s*1/, 'needs more than one domain';
  like $branch, qr/count\(DISTINCT\s+\w+\.vrf\)\s*>\s*1/, 'needs more than one spelling';
  like $branch, qr/lower\(regexp_replace\(\w+\.vrf, '\[\^A-Za-z0-9\]', '', 'g'\)\)/, 'normalized key';
};

subtest 'virtual__shared_rd__null_rd_excluded' => sub {
  my ($branch) = grep { /'shared RD'/ } @branches;
  like $branch, qr/\.rd IS NOT NULL/, 'NULL rd excluded';
  like $branch, qr/count\(DISTINCT\s+\w+\.domain_id\)\s*>\s*1/, 'needs more than one domain';
};

subtest 'virtual__linked_one_subnet__pair_reported_once' => sub {
  my ($branch) = grep { /'linked, one subnet'/ } @branches;
  like $branch, qr/device_ip_resolved/, 'neighbor resolved through device_ip_resolved';
  like $branch, qr/IS DISTINCT FROM/, 'missing member counts as a different domain';
  like $branch, qr/SELECT DISTINCT/, 'both directions fold to one pair';
};

my @rows = (
  { finding => 'different names', domain => 'RED', vrfs => ['RED', 'Red'], devices => 2, detail => 'domain holds RED, Red',
    domain_ids => [11], domains => 'RED (#11)' },
  { finding => 'shared RD', domain => 'BLUE', vrfs => ['BLUE', 'GREEN'], devices => 2, detail => 'RD 65000:1' },
);

# the stash the route's template sees, as Web.pm fills it for every render
sub report_html {
  my @results = @_;
  return render_template('ajax/report/vrfinconsistency.tt',
    { results => to_json(\@results), uri_for => sub { $_[0] } });
}

subtest 'templates__results_empty_and_filled__render' => sub {
  foreach my $case (['empty', []], ['filled', \@rows]) {
    my ($label, $results) = @$case;
    my ($html, $error) = report_html(@$results);
    is $error, undef, "html renders ($label)";
    like $html, qr/VRF Naming|<th>Finding<\/th>/, 'has the Finding column';
    like $html, qr/RED/, 'carries the rows' if $label eq 'filled';

    my ($csv, $csv_error) = render_template('ajax/report/vrfinconsistency_csv.tt', { results => $results, headings => [] });
    is $csv_error, undef, "csv renders ($label)";
    like $csv, qr/^Finding,Domains,VRFs,Devices,Detail/, 'csv header';
    like $csv, qr/^"different names","RED \(#11\)","RED,Red",2,"domain holds RED, Red"$/m, 'csv names every domain with its id'
      if $label eq 'filled';
  }
};

subtest 'template__vrf_name_with_markup__cannot_close_the_json_block' => sub {
  my $hostile = '</script><b>R&D</b>';
  my ($html, $error) = report_html(
    { finding => 'shared RD', domain => $hostile, vrfs => [$hostile], devices => 1, detail => $hostile });
  is $error, undef, 'renders';
  unlike $html, qr{</script><b>}, 'no raw markup from device data';
  is from_json(json_block($html))->[0]{detail}, $hostile, 'carried intact';
};

subtest 'virtual__linked_branch__pairs_reduced_before_device_ip_join' => sub {
  my ($branch) = grep { /'linked, one subnet'/ } @branches;
  my $pairs = index $branch, 'FROM device_port';
  my $join  = index $branch, 'JOIN device_ip ia';
  ok $pairs >= 0 && $join > $pairs, 'device_port pairs come before the device_ip join';
  like $branch, qr/SELECT DISTINCT\s+dp\.ip\s+AS\s+a_ip,\s*dp\.port\s+AS\s+a_port,\s*r\.ip\s+AS\s+b_ip/,
    'distinct device and port pairs first';
};

# two neighbors linked in the default table, each reusing 192.168.77.0/24 in
# its own customer VRF, were reported as one subnet split across two domains
subtest 'virtual__linked_subnet_off_the_neighbor_port__not_paired' => sub {
  my ($branch) = grep { /'linked, one subnet'/ } @branches;
  like $branch, qr/JOIN device_ip ia ON ia\.ip = pr\.a_ip[^\n]*\n\s*AND \(ia\.port = pr\.a_port OR left\(ia\.port, length\(pr\.a_port\) \+ 1\) = pr\.a_port \|\| '\.'\)/,
    'the subnet is on the neighbor port or one of its subinterfaces';
};

subtest 'virtual__similar_names__empty_normalized_excluded' => sub {
  my ($branch) = grep { /'similar names'/ } @branches;
  like $branch, qr/lower\(regexp_replace\(m\.vrf, '\[\^A-Za-z0-9\]', '', 'g'\)\)\s*<>\s*''/,
    'names that normalize to nothing are left out';
};

subtest 'virtual__linked_same_address_both_sides__not_reported' => sub {
  my ($branch) = grep { /'linked, one subnet'/ } @branches;
  like $branch, qr/ia\.alias\s*<>\s*ib\.alias/, 'the two sides must hold different addresses';
};

# two neighbors carrying one subnet in RED and again in BLUE paired RED with
# BLUE, and reported two correctly separate domains as needing to be one
subtest 'virtual__linked_subnet_in_two_vrfs_on_a_side__not_paired' => sub {
  my ($branch) = grep { /'linked, one subnet'/ } @branches;
  for my $side (qw/ia ib/) {
    like $branch, qr/NOT EXISTS\s*\(\s*SELECT 1 FROM device_ip \w+\s+WHERE \w+\.ip = $side\.ip AND \w+\.subnet = $side\.subnet\s+AND \w+\.vrf <> '' AND \w+\.vrf <> $side\.vrf\s*\)/,
      "$side: a subnet in another named VRF on the same device is not paired";
  }
};

# domain names repeat, so a finding links to the L3 Domains report by id, with
# every domain it involves; that report lists each device and VRF, so the
# finding itself carries no per-device columns
subtest 'virtual__every_branch__domain_ids_and_names' => sub {
  my %expect = (
    'different names'    => qr/ARRAY\[d\.id\] AS domain_ids/,
    'similar names'      => qr/array_agg\(DISTINCT m\.domain_id ORDER BY m\.domain_id\) AS domain_ids/,
    'shared RD'          => qr/array_agg\(DISTINCT m\.domain_id ORDER BY m\.domain_id\) AS domain_ids/,
    'linked, one subnet' => qr/NULLIF\(array_remove\(ARRAY\[p\.lo_domain, p\.hi_domain\], NULL\), '\{\}'\) AS domain_ids/,
  );
  foreach my $branch (@branches) {
    my ($finding) = $branch =~ /'([^']+)' AS finding/;
    like $branch, $expect{$finding}, "$finding domain_ids";
    like $branch, qr/string_agg\(x\.name \|\| ' \(#' \|\| x\.id \|\| '\)', ', ' ORDER BY x\.id\) FROM l3_domain x WHERE x\.id = ANY\(.+?\)\) AS domains/,
      "$finding names its domains with their ids, in id order";
    unlike $branch, qr/lo_dns|hi_name|::text AS subnet\b/, "$finding has no per-device columns";
  }
  my ($linked) = grep { /'linked, one subnet'/ } @branches;
  like $linked, qr/CASE WHEN l\.a_ip < l\.b_ip THEN l\.b_domain ELSE l\.a_domain END AS hi_domain/, 'the high side keeps its domain';
  my $source = App::Netdisco::DB::Result::Virtual::VrfInconsistency->result_source_instance;
  ok $source->has_column($_), "$_ is a column" for qw/domain_ids domains/;
  ok !$source->has_column($_), "$_ is gone" for qw/subnet lo_ip hi_ip lo_dns lo_name hi_dns hi_name/;
};

sub json_block {
  my $html = shift;
  my ($json) = $html =~ m{<script type="application/json" id="nd-results-report-vrfinconsistency">(.*?)</script>}s;
  return $json;
}

sub table_columns {
  my $html = shift;
  my ($table) = $html =~ m{data-nd-table='(.*?)'}s;
  return @{ from_json($table)->{columns} };
}

subtest 'template__findings__json_block_and_renderers' => sub {
  my ($html, $error) = report_html({ %{ $rows[0] }, domain_ids => [11, 14], domains => 'RED, Red' });
  is $error, undef, 'renders';
  is from_json(json_block($html))->[0]{domain_ids}[1], 14, 'rows travel as JSON';
  my @cols = table_columns($html);
  is_deeply [ map { $_->{data} } @cols ], [qw/finding domains vrfs devices detail/], 'column order';
  my %render = map { $_->{data} => $_->{render} } @cols;
  is_deeply $render{domains}, { name => 'reportLink', report => 'report_l3domains', param => 'domain',
    key => 'domain_ids', show => 'domains', blankText => 'not grouped' }, 'domains link by id';
  is_deeply $render{vrfs}, { name => 'join', key => 'vrfs', with => ', ' }, 'VRF names joined';
  is $render{detail}, 'escape', 'detail is text';
  like $html, qr{"report_l3domains":\s*"/report/l3domains"}, 'url for the link';
  unlike $html, qr{<tbody>}, 'no server-rendered rows';
};

done_testing;
