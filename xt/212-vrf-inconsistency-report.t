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
  { finding => 'different names', domain => 'RED', vrfs => ['RED', 'Red'], devices => 2, detail => 'domain holds RED, Red' },
  { finding => 'shared RD', domain => 'BLUE', vrfs => ['BLUE', 'GREEN'], devices => 2, detail => 'RD 65000:1' },
);

# the stash the route's template sees, as Web.pm fills it for every render
sub report_html {
  my @results = @_;
  return render_template('ajax/report/vrfinconsistency.tt',
    { results => \@results, uri_for => sub { $_[0] }, search_device => '/search?tab=device' });
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
    like $csv, qr/^Finding,Domain,VRFs,Devices,Detail/, 'csv header';
    like $csv, qr/^"different names",RED,"RED,Red",2,"domain holds RED, Red"$/m, 'csv row joins the names'
      if $label eq 'filled';
  }
};

subtest 'template__vrf_name_with_markup__escaped_in_the_cells' => sub {
  my $hostile = '</script><b>R&D</b>';
  my ($html, $error) = report_html(
    { finding => 'shared RD', domain => $hostile, vrfs => [$hostile], devices => 1, detail => $hostile });
  is $error, undef, 'renders';
  unlike $html, qr{<b>R&D</b>}, 'no raw markup from device data';
  like $html, qr{&lt;/script&gt;&lt;b&gt;R&amp;D&lt;/b&gt;}, 'escaped';
};

subtest 'virtual__linked_branch__pairs_reduced_before_device_ip_join' => sub {
  my ($branch) = grep { /'linked, one subnet'/ } @branches;
  my $pairs = index $branch, 'FROM device_port';
  my $join  = index $branch, 'JOIN device_ip ia';
  ok $pairs >= 0 && $join > $pairs, 'device_port pairs come before the device_ip join';
  like $branch, qr/SELECT DISTINCT\s+dp\.ip\s+AS\s+a_ip,\s*r\.ip\s+AS\s+b_ip/, 'distinct device pairs first';
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

# The detail sentence of a linked finding names a subnet and two devices; the
# report links each, so the view returns them as their own columns rather than
# leaving the renderer to read them back out of the text.
subtest 'virtual__linked_branch__subnet_and_both_ends_as_columns' => sub {
  my ($branch) = grep { /'linked, one subnet'/ } @branches;
  like $branch, qr/p\.subnet::text AS subnet,\s*host\(p\.lo_ip\) AS lo_ip,\s*host\(p\.hi_ip\) AS hi_ip,\s*dl\.dns AS lo_dns,\s*dl\.name AS lo_name,\s*dh\.dns AS hi_dns,\s*dh\.name AS hi_name/,
    'subnet, and the address, stored DNS name and name of each device';
  like $branch, qr/LEFT JOIN device dl ON dl\.ip = p\.lo_ip\s+LEFT JOIN device dh ON dh\.ip = p\.hi_ip/, 'each end joined to its device';
  foreach my $other (grep { !/'linked, one subnet'/ } @branches) {
    my ($finding) = $other =~ /'([^']+)' AS finding/;
    like $other, qr/NULL::text AS subnet,\s*NULL::text AS lo_ip,\s*NULL::text AS hi_ip,\s*NULL::text AS lo_dns,\s*NULL::text AS lo_name,\s*NULL::text AS hi_dns,\s*NULL::text AS hi_name/, "$finding has none";
  }
  my $source = App::Netdisco::DB::Result::Virtual::VrfInconsistency->result_source_instance;
  foreach my $column (qw/subnet lo_ip hi_ip lo_dns lo_name hi_dns hi_name/) {
    ok $source->has_column($column), "$column is a column";
    ok $source->column_info($column)->{is_nullable}, "$column is nullable";
  }
};

subtest 'template__linked_row__links_the_subnet_and_both_devices' => sub {
  my ($html, $error) = report_html({ finding => 'linked, one subnet', domain => 'RED', vrfs => ['RED', 'Red'],
    devices => 2, detail => 'subnet 10.110.23.0/30 between 172.20.20.62 and 172.20.20.63',
    subnet => '10.110.23.0/30', lo_ip => '172.20.20.62', hi_ip => '172.20.20.63',
    lo_dns => 'r2.lab.example', lo_name => 'r2', hi_dns => undef, hi_name => 'r3' });
  is $error, undef, 'renders';
  (my $flat = $html) =~ s/\s+/ /g;
  like $flat, qr{subnet <a href="/search\?tab=device&q=10\.110\.23\.0%2F30&ip=10\.110\.23\.0%2F30">10\.110\.23\.0/30</a>},
    'the subnet links to the devices in it';
  like $flat, qr{between <a href="/device\?q=172\.20\.20\.62">r2\.lab\.example</a> and <a href="/device\?q=172\.20\.20\.63">r3</a>},
    'each end links to its device, labelled DNS name, else name';
};

subtest 'template__other_findings__detail_as_text' => sub {
  my ($html, $error) = report_html(@rows);
  is $error, undef, 'renders';
  like $html, qr{domain holds RED, Red}, 'detail shown';
  unlike $html, qr{<a href}, 'nothing to link';
};

subtest 'template__linked_row_device_unnamed__labelled_by_address' => sub {
  my ($html, $error) = report_html({ finding => 'linked, one subnet', domain => '', vrfs => ['A', 'B'], devices => 2,
    detail => 'subnet 10.0.0.0/30 between 10.0.0.1 and 10.0.0.2', subnet => '10.0.0.0/30',
    lo_ip => '10.0.0.1', hi_ip => '10.0.0.2', lo_dns => '', lo_name => undef, hi_dns => undef, hi_name => '' });
  is $error, undef, 'renders';
  like $html, qr{<a href="/device\?q=10\.0\.0\.1">10\.0\.0\.1</a>}, 'no DNS name or name: the address';
  like $html, qr{<a href="/device\?q=10\.0\.0\.2">10\.0\.0\.2</a>}, 'empty strings count as unset';
};

done_testing;
