#!/usr/bin/env perl

# Subnet Utilization, IP Inventory and the shipped shared and duplicate address
# reports count an address only within its L3 domain, so the same space reused
# in two VRFs is neither merged nor reported as sharing. A default-table row
# (vrf = '') is domain 0 without calling l3_domain_of. CI has no database, so
# the SQL is checked as text and the templates are rendered with stub rows.
#
# The two-domain renderings are compared with *.two-domains.html files beside
# the xt/40 snapshots. After a deliberate template change, rewrite them with:
#   ND_WRITE_DOMAIN_SNAPSHOTS=1 prove -Ilib -Ixt/lib xt/188-vrf-domain-readers.t

use strict;
use warnings;

use Test::More 0.88;
use NetAddr::IP::Lite;
use YAML::XS ();
use App::Netdisco::DB;
use App::Netdisco::Util::L3Domain qw/results_span_domains label_rows_by_domain/;
use JSON::PP ();
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template snapshot_path/;

my $DEFAULT_ROW_GUARD = qr/CASE WHEN (\w+)\.vrf = '' THEN 0 ELSE l3_domain_of\(\1\.\w+, \1\.vrf\) END/;

sub slurp {
  my $file = shift;
  open my $fh, '<', $file or die "$file: $!";
  local $/;
  return scalar <$fh>;
}

my $subnet_sql = (slurp('lib/App/Netdisco/DB/Result/Virtual/SubnetUtilization.pm')
  =~ /<<'ENDSQL'\);\n(.*?)\nENDSQL/s)[0] // '';

# the domain-aware never-seen form, as when a named-VRF subnet overlaps
{
  no warnings 'redefine';
  *App::Netdisco::DB::ResultSet::DeviceIp::_named_vrf_subnet_overlaps = sub { 1 };
}

my $inventory_sql = do {
  my $schema = do {
    local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
    my $s = App::Netdisco::DB->clone;
    $s->storage_type('::DBI::Pg');
    $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
    $s;
  };
  my $rs = $schema->resultset('DeviceIp')->ip_inventory(
    NetAddr::IP::Lite->new('10.0.0.0/24'), { never => 1, limit => 256 });
  ${ $rs->as_query }->[0];
};

my %report = map { $_->{tag} => $_ }
  @{ YAML::XS::LoadFile('share/config.yml')->{system_reports} };

subtest 'subnet_utilization__sql__matches_addresses_within_one_domain' => sub {
  ok(length $subnet_sql, 'found the view definition');
  # each subnet's domain is computed once per row in a DISTINCT subquery, and
  # each address's beside the containment join; OFFSET 0 holds the domain
  # comparison above that join, so it is a filter and never a join key
  my $subnet_side = () = $subnet_sql =~ /SELECT DISTINCT s\.net, s\.last_discover,\s+CASE WHEN s\.vrf = '' THEN 0 ELSE l3_domain_of\(s\.router_last, s\.vrf\) END AS domain\s+FROM subnets s\) s[12]\b/g;
  is($subnet_side, 2, 'a subnet takes its domain from the device that reported it, once per row');
  unlike($subnet_sql, qr/FROM subnets s OFFSET 0/, 'no OFFSET 0 on the subnet side, which would cost the parallel plan');
  like($subnet_sql, qr/CASE WHEN ni\.vrf = '' THEN 0 ELSE l3_domain_of\(ni\.router_last, ni\.vrf\) END AS ip_domain/,
    'a node address takes its domain from the device that reported it');
  like($subnet_sql, qr/CASE WHEN di\.vrf = '' THEN 0 ELSE l3_domain_of\(di\.ip, di\.vrf\) END AS ip_domain/,
    'a device address takes its domain from its own device');
  my $fences = () = $subnet_sql =~ /\n\s+OFFSET 0\) pairs\n\s+WHERE pairs\.ip_domain = pairs\.domain\n/g;
  is($fences, 2, 'each half compares domains above an OFFSET 0 fence');
  unlike($subnet_sql, qr/\.domain = s[12]\.domain|LATERAL/, 'the domain is not a join key');
  like($subnet_sql, qr/AND ni\.ip <<= s1\.net\n/, 'node addresses join their subnet on containment');
  like($subnet_sql, qr/AND di\.alias <<= s2\.net\n/, 'device addresses join their subnet on containment');
  my $distinct = () = $subnet_sql =~ /SELECT DISTINCT pairs\.domain, pairs\.net, pairs\.ip\n/g;
  is($distinct, 2, 'each half keeps the domain in its DISTINCT');
  my $calls = () = $subnet_sql =~ /l3_domain_of\(/g;
  is($calls, 4, 'no other call to l3_domain_of');
  like($subnet_sql, qr/GROUP BY joined\.domain, net, ld\.name/, 'grouped by domain and net');
  like($subnet_sql, qr/JOIN l3_domain ld ON ld\.id = joined\.domain/, 'labeled from l3_domain');
  like($subnet_sql, qr/ld\.name as vrf/, 'the label is the vrf output column');
  ok(App::Netdisco::DB->source('Virtual::SubnetUtilization')->has_column('vrf'),
    'the result class declares vrf');
};

subtest 'ip_inventory__distinct_on__ip_then_domain' => sub {
  like($inventory_sql, qr/DISTINCT ON \(ip, domain\)/, 'one row per IP and domain');
  # ip leads the sort key: with every row in domain 0, a domain-first key
  # made each comparison of a large sort fall through to ip
  like($inventory_sql, qr/ORDER BY ip ASC, domain ASC, CASE WHEN active AND NOT node THEN 0/,
    'ip, then domain, then the existing tie-break order');
  like($inventory_sql, qr/CASE WHEN me\.vrf = '' THEN 0 ELSE l3_domain_of\(me\.ip, me\.vrf\) END AS domain/,
    'device addresses take the domain of their own device');
  like($inventory_sql, qr/CASE WHEN me\.vrf = '' THEN 0 ELSE l3_domain_of\(me\.router_last, me\.vrf\) END AS domain/,
    'node addresses take the domain of the device that reported them');
  my $zeros = () = $inventory_sql =~ /\b0 AS domain\b/g;
  is($zeros, 1, 'NetBIOS rows are domain 0');
  like($inventory_sql, qr/\bo\.domain\s+FROM addr a\b/,
    'generated never-seen rows take their stored subnet\'s domain');
  like($inventory_sql, qr/SELECT g\.int, 0 FROM addr\b/, 'else domain 0');
  like($inventory_sql, qr/domain IS NOT NULL/, 'a row with no single domain is left out');
  like($inventory_sql, qr/\(SELECT ld\.name FROM l3_domain ld WHERE ld\.id = me\.domain\) AS vrf/,
    'each row is labeled with its domain name');
};

subtest 'shipped_reports__shared_and_duplicate__group_by_domain' => sub {
  my $shared = $report{devicesharedaddresses}{query};
  like($shared, qr/GROUP BY domain, alias, ld\.name\b/, 'shared addresses group by domain and alias');
  like($shared, qr/domain IS NOT NULL/, 'and leave out a row with no single domain');
  my $duplicate = $report{duplicateprivatenetworks}{query};
  like($duplicate, qr/GROUP BY domain, subnet, ld\.name\b/, 'duplicate networks group by domain and subnet');
  like($duplicate, qr/domain IS NOT NULL/, 'and leave out a row with no single domain');
  is_deeply([ map { grep { !/^_/ } keys %$_ } @{ $report{devicesharedaddresses}{columns} } ],
    [qw/alias vrf count/], 'shared addresses gain only the VRF column');
  is_deeply([ map { grep { !/^_/ } keys %$_ } @{ $report{duplicateprivatenetworks}{columns} } ],
    [qw/subnet vrf count seen/], 'duplicate networks gain only the VRF column');
};

subtest 'shipped_reports__multiple_addresses__count_distinct_alias' => sub {
  my $multiple = $report{devicemultipleaddresses}{query};
  my $distinct = () = $multiple =~ /count\(DISTINCT alias\)/g;
  is($distinct, 3, 'select, HAVING and ORDER BY count each alias once');
  unlike($multiple, qr/count\(alias\)/, 'no count of rows');
};

subtest 'readers__switch_off_form__no_function_call_for_default_rows' => sub {
  my %sources = (
    'Subnet Utilization' => $subnet_sql,
    'IP Inventory' => $inventory_sql,
    'Node search domain' => slurp('lib/App/Netdisco/DB/ResultSet/NodeIp.pm'),
    map { ($_ => $report{$_}{query}) }
      qw/devicesharedaddresses duplicateprivatenetworks/,
  );
  foreach my $name (sort keys %sources) {
    my $calls = () = $sources{$name} =~ /l3_domain_of\(/g;
    my $guarded = () = $sources{$name} =~ /$DEFAULT_ROW_GUARD/g;
    cmp_ok($calls, '>', 0, "$name calls l3_domain_of");
    is($guarded, $calls, "$name calls it only in the ELSE of vrf = ''");
  }
};

subtest 'results_span_domains__rows__true_for_two_names_or_any_named' => sub {
  ok(!results_span_domains([]), 'no rows');
  ok(results_span_domains([ { vrf => 'RED' } ]), 'one named domain');
  ok(results_span_domains([ { vrf => '' }, { vrf => 'RED' } ]), 'default and named');
};

subtest 'results_span_domains__all_default__false' => sub {
  ok(!results_span_domains([ { vrf => '' }, { vrf => '' } ]), 'default table only');
  ok(!results_span_domains([ { vrf => undef } ]), 'no name reads as the default table');
};

subtest 'results_span_domains__single_named_domain__true' => sub {
  ok(results_span_domains([ { vrf => 'RED' }, { vrf => 'RED' } ]), 'every row in RED');
};

my %subnet_rows = (
  one => [ { subnet => '10.0.0.0/24', vrf => '', subnet_size => 256, active => 5, percent => 2 } ],
  two => [ { subnet => '10.0.0.0/24', vrf => '', subnet_size => 256, active => 5, percent => 2 },
           { subnet => '10.0.0.0/24', vrf => 'RED', subnet_size => 256, active => 9, percent => 4 } ],
);
my %inventory_rows = (
  one => [ { ip => '10.0.0.1', vrf => '', mac => '00:00:5e:00:53:01', vendor => 'IANA',
             dns => 'a.example.com', nbname => undef, time_last => '2026-11-01 10:00:00' } ],
  two => [ { ip => '10.0.0.1', vrf => '', mac => '00:00:5e:00:53:01', vendor => 'IANA',
             dns => 'a.example.com', nbname => undef, time_last => '2026-11-01 10:00:00' },
           { ip => '10.0.0.1', vrf => 'RED', mac => '00:00:5e:00:53:02', vendor => 'IANA',
             dns => undef, nbname => undef, time_last => '2026-11-01 11:00:00' } ],
);
# the HTML view of IP Inventory gets JSON, shaped as its route handler does
sub to_json_text { JSON::PP->new->canonical->encode(shift) }

sub stash {
  my ($view, $domains) = @_;
  my $multi = $domains eq 'two' ? 1 : 0;
  my $rows = $view =~ /subnets/ ? $subnet_rows{$domains} : $inventory_rows{$domains};
  $rows = to_json_text(label_rows_by_domain($rows, $multi))
    if $view eq 'ajax/report/ipinventory.tt';
  return { results => $rows, multi_domain => $multi,
           settings => { thousands_separator => ',' } };
}

subtest 'label_rows_by_domain__one_or_two_domains__shapes_rows_for_the_browser' => sub {
  is_deeply(label_rows_by_domain([ { ip => '10.0.0.1', vrf => '' } ], 0),
    [ { ip => '10.0.0.1' } ], 'one domain: no vrf key, as before domains');
  is_deeply(label_rows_by_domain([ { ip => '10.0.0.1', vrf => '' }, { ip => '10.0.0.1', vrf => 'RED' } ], 1),
    [ { ip => '10.0.0.1', vrf => 'default' }, { ip => '10.0.0.1', vrf => 'RED' } ],
    'two domains: the default table is labeled default');
  my $rows = [ { ip => '10.0.0.1', vrf => '' } ];
  label_rows_by_domain($rows, 1);
  is($rows->[0]{vrf}, '', 'the caller\'s rows are left unchanged');
};

my @views = map { "ajax/report/$_.tt" } qw/subnets subnets_csv ipinventory ipinventory_csv/;

subtest 'report_templates__single_named_domain__vrf_column_shows_the_name' => sub {
  my %red = (
    subnets   => [ { %{ $subnet_rows{one}[0] }, vrf => 'RED' } ],
    inventory => [ { %{ $inventory_rows{one}[0] }, vrf => 'RED' } ],
  );
  foreach my $view (@views) {
    my $rows = $view =~ /subnets/ ? $red{subnets} : $red{inventory};
    my $multi = results_span_domains($rows);
    $rows = to_json_text(label_rows_by_domain($rows, $multi)) if $view eq 'ajax/report/ipinventory.tt';
    my ($html, $error) = render_template($view,
      { results => $rows, multi_domain => $multi, settings => { thousands_separator => ',' } });
    is($error, undef, "$view renders");
    like($html, qr/VRF/, "$view has a VRF column");
    like($html, qr/RED/, "$view shows the domain name");
  }
};

subtest 'report_templates__one_domain__no_vrf_column' => sub {
  foreach my $view (@views) {
    my ($html, $error) = render_template($view, stash($view, 'one'));
    is($error, undef, "$view renders");
    unlike($html, qr/VRF/, "$view has no VRF column");

    my $before = stash($view, 'one');
    delete $before->{multi_domain};
    my $source = $view =~ /subnets/ ? $subnet_rows{one} : $inventory_rows{one};
    my $today_rows = [ map { my %r = %$_; delete $r{vrf}; \%r } @$source ];
    $before->{results} = $view eq 'ajax/report/ipinventory.tt'
      ? to_json_text($today_rows) : $today_rows;
    my ($today) = render_template($view, $before);
    is($html, $today, "$view renders as it did before domains");
  }
};

subtest 'report_templates__two_domains__vrf_column_labels_default_and_name' => sub {
  foreach my $view (@views) {
    my ($html, $error) = render_template($view, stash($view, 'two'));
    is($error, undef, "$view renders");
    like($html, qr/VRF/, "$view has a VRF column");
    like($html, qr/default/, "$view labels domain 0 as default");
    like($html, qr/RED/, "$view labels a named domain by its name");

    SKIP: {
      skip 'xt/snapshots is not shipped in the distribution', 1
        unless -d 'xt/snapshots';
      my $path = snapshot_path($view) =~ s/\.html\z/.two-domains.html/r;
      if ($ENV{ND_WRITE_DOMAIN_SNAPSHOTS}) {
        open my $fh, '>:encoding(UTF-8)', $path or die "$path: $!";
        print {$fh} $html;
        close $fh;
      }
      open my $fh, '<:encoding(UTF-8)', $path or do { fail("$path is missing"); next };
      my $want = do { local $/; <$fh> };
      is($html, $want, "$view matches $path");
    }
  }

  my ($subnets) = render_template('ajax/report/subnets.tt', stash('ajax/report/subnets.tt', 'two'));
  like($subnets, qr/"order":\[\[4,"desc"\]\]/, 'subnets still sorts on Percent Utilization');
  my ($inventory) = render_template('ajax/report/ipinventory.tt', stash('ajax/report/ipinventory.tt', 'two'));
  like($inventory, qr/\{"data":"vrf","render":"escape"\}/, 'IP Inventory defines the VRF column');
};

done_testing;
