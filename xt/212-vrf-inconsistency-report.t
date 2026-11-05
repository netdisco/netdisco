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
use JSON::PP ();
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

subtest 'templates__results_empty_and_filled__render' => sub {
  my $json = JSON::PP->new->canonical->encode(\@rows);
  foreach my $case (['empty', '[]', []], ['filled', $json, \@rows]) {
    my ($label, $html_results, $csv_results) = @$case;
    my ($html, $error) = render_template('ajax/report/vrfinconsistency.tt', { results => $html_results });
    is $error, undef, "html renders ($label)";
    like $html, qr/VRF Naming|<th>Finding<\/th>/, 'has the Finding column';
    like $html, qr/RED/, 'carries the rows' if $label eq 'filled';

    my ($csv, $csv_error) = render_template('ajax/report/vrfinconsistency_csv.tt', { results => $csv_results, headings => [] });
    is $csv_error, undef, "csv renders ($label)";
    like $csv, qr/^Finding,Domain,VRFs,Devices,Detail/, 'csv header';
    like $csv, qr/^"different names",RED,"RED,Red",2,"domain holds RED, Red"$/m, 'csv row joins the names'
      if $label eq 'filled';
  }
};

subtest 'template__vrf_name_with_markup__escaped_in_data_block' => sub {
  my $hostile = '</script><b>R&D</b>';
  my $json = JSON::PP->new->canonical->encode([
    { finding => 'shared RD', domain => 'X', vrfs => [$hostile], devices => 1, detail => $hostile },
  ]);
  my ($html, $error) = render_template('ajax/report/vrfinconsistency.tt', { results => $json });
  is $error, undef, 'renders';
  unlike $html, qr{</script><b>}, 'no raw script terminator from device data';
  like $html, qr/\\u003c\/script>\\u003cb>R&D/, 'the data block escapes <';
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

done_testing;
