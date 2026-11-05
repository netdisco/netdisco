#!/usr/bin/env perl

# With store_vrfs on, the same address can be listed once per VRF. Every page
# that lists such rows labels each with its VRF, so the copies do not look like
# duplicates, and shows no label when every row is in the default table, so a
# site that never turns VRFs on sees the same pages as before. CI has no
# database, so these tests check helpers, SQL text and template renderings.

use strict;
use warnings;

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };
use YAML::XS ();
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template snapshot_path/;

use App::Netdisco::Util::Web 'omit_empty_columns';
use App::Netdisco::Util::L3Domain qw/results_span_domains label_rows_by_domain/;
use JSON::PP ();
use JSON ();
use NetAddr::IP::Lite;
use App::Netdisco::DB;

my %report = map { ($_->{tag} => $_) }
  @{ YAML::XS::LoadFile('share/config.yml')->{system_reports} };

my %vrf_options = (_omit_if_empty => 1, _empty_as => 'default');

subtest 'omit_empty_columns__all_empty__drops_column_and_keys' => sub {
  my @rows = ({ alias => '10.0.0.1', count => 2, vrf => '' },
              { alias => '10.0.0.2', count => 3 });
  my @kept = omit_empty_columns(\@rows, [qw/alias count vrf/],
    { alias => {}, count => {}, vrf => { %vrf_options } });
  is_deeply(\@kept, [qw/alias count/], 'vrf column dropped');
  ok(!grep({ exists $_->{vrf} } @rows), 'and its key removed from every row');
};

subtest 'omit_empty_columns__one_named__keeps_column_and_labels_default' => sub {
  my @rows = ({ alias => '10.0.0.1', count => 2, vrf => '' },
              { alias => '10.0.0.1', count => 2, vrf => 'RED' });
  my @kept = omit_empty_columns(\@rows, [qw/alias vrf count/],
    { alias => {}, count => {}, vrf => { %vrf_options } });
  is_deeply(\@kept, [qw/alias vrf count/], 'every column kept, in order');
  is_deeply([ map { $_->{vrf} } @rows ], [qw/default RED/], 'empty reads default');
};

subtest 'omit_empty_columns__no_options__unchanged' => sub {
  my @rows = ({ alias => '', count => 2 });
  my @kept = omit_empty_columns(\@rows, [qw/alias count/],
    { alias => { _searchable => 1 }, count => {} });
  is_deeply(\@kept, [qw/alias count/], 'columns without the options are kept');
  is_deeply(\@rows, [{ alias => '', count => 2 }], 'and their values untouched');
};

subtest 'omit_empty_columns__column_without_options__numbers_stay_numbers' => sub {
  # the report API serializes these rows; reading a number as a string makes
  # the JSON encoder emit "2" instead of 2 for every column of every report
  my @rows = ({ alias => '10.0.0.1', count => 2, vrf => '' });
  omit_empty_columns(\@rows, [qw/alias count vrf/],
    { alias => {}, count => {}, vrf => { %vrf_options } });
  # JSON is the encoder Dancer's to_json uses; JSON::PP does not show this
  is(JSON->new->canonical->encode(\@rows), '[{"alias":"10.0.0.1","count":2}]',
    'count is still a JSON number');
};

subtest 'shipped_reports__shared_and_duplicate__vrf_column_omitted_when_empty' => sub {
  foreach my $tag (qw/devicesharedaddresses duplicateprivatenetworks/) {
    my ($vrf) = grep { exists $_->{vrf} } @{ $report{$tag}{columns} };
    ok($vrf, "$tag has a vrf column");
    is($vrf->{vrf}, 'VRF', "$tag heading");
    ok($vrf->{_omit_if_empty}, "$tag drops it when empty");
    is($vrf->{_empty_as}, 'default', "$tag labels domain 0 default");
    like($report{$tag}{query}, qr/JOIN l3_domain ld ON ld\.id = di\.domain/, "$tag joins the domain");
    like($report{$tag}{query}, qr/ld\.name AS vrf/, "$tag selects its name");
  }
};

subtest 'generic_report_controller__applies_column_options_to_every_output' => sub {
  # without this call a shipped report's VRF column shows, empty, on every site
  my $src = do { local (@ARGV, $/) = 'lib/App/Netdisco/Web/GenericReport.pm'; <> };
  my $munger = index($src, 'my @results = ((-f $munger)');
  my $omit = index($src, '@column_order = omit_empty_columns(\@results, \@column_order, \%column_config);');
  my $branch = index($src, 'if (request->is_ajax) {');
  cmp_ok($omit, '>', $munger, 'applied after the site munger');
  cmp_ok($omit, '<', $branch, 'and before the HTML, CSV and API outputs split');
};

subtest 'generic_report_template__vrf_named__escaped' => sub {
  my ($html, $error) = render_template('ajax/report/generic_report.tt', {
    results => [{ alias => '10.0.0.1', vrf => '<b>R&D</b>', count => 2 }],
    column_options => { alias => {}, vrf => {}, count => {} },
    headings => [qw/Alias VRF Count/],
    columns => [qw/alias vrf count/],
  });
  is($error, undef, 'renders');
  like($html, qr/&lt;b&gt;R&amp;D&lt;\/b&gt;/, 'the VRF name is escaped');
};

subtest 'generic_report_csv__vrf_kept__header_and_row_arity_match' => sub {
  my ($csv, $error) = render_template('ajax/report/generic_report_csv.tt', {
    results => [{ alias => '10.0.0.1', vrf => 'default', count => 2 },
                { alias => '10.0.0.1', vrf => 'RED', count => 2 }],
    headings => [qw/Alias VRF Count/],
    columns => [qw/alias vrf count/],
  });
  is($error, undef, 'renders');
  my @lines = grep { /\S/ } split /\r?\n/, $csv;
  is(scalar @lines, 3, 'header and two rows');
  is_deeply([ map { scalar(() = /,/g) } @lines ], [2, 2, 2], 'three fields on every line');
};

# The Addresses tab lists one device's own addresses, so it labels each with
# the device's local VRF name (design 4.10), through the same helpers as the
# domain-aware reports.
sub address_rows {
  my @vrfs = @_;
  return [ map { { alias => '10.250.1.1', vrf => $_, dns => 'leaf01-vlan10',
                   port => 'Vlan10', subnet => '10.250.1.0/24',
                   device_port => { name => 'servers' } } } @vrfs ];
}

sub addresses_stash {
  my ($rows, $csv) = @_;
  my $multi = results_span_domains($rows);
  my $labeled = label_rows_by_domain($rows, $multi);
  return { results => ($csv ? $labeled : JSON::PP->new->canonical->encode($labeled)),
           multi_domain => $multi, user_has_role => sub { 0 } };
}

subtest 'addresses_templates__default_only__no_vrf_column' => sub {
  my $rows = address_rows('', '');
  my ($html, $error) = render_template('ajax/device/addresses.tt', addresses_stash($rows));
  is($error, undef, 'renders');
  unlike($html, qr/VRF|"vrf"/, 'no VRF column and no vrf key in the data');
  my ($csv) = render_template('ajax/device/addresses_csv.tt', addresses_stash($rows, 1));
  like($csv, qr/^Address,DNS,Interface,Description,Prefix\r?$/m, 'CSV header as before');
};

subtest 'addresses_templates__two_vrfs__vrf_column_after_address' => sub {
  my $rows = address_rows('', 'blue');
  my ($html, $error) = render_template('ajax/device/addresses.tt', addresses_stash($rows));
  is($error, undef, 'renders');
  like($html, qr{<th>Address</th>\s*<th>VRF</th>}, 'VRF header after Address');
  like($html, qr/\{"data":"alias","render":"escape"\},\s*\{"data":"vrf","render":"escape"\}/,
    'VRF is the second column');
  like($html, qr/"vrf":"default"/, 'default table reads default');
  like($html, qr/"vrf":"blue"/, 'named VRF by its local name');

  my ($csv) = render_template('ajax/device/addresses_csv.tt', addresses_stash($rows, 1));
  my @lines = grep { /\S/ } split /\r?\n/, $csv;
  is($lines[0], 'Address,VRF,DNS,Interface,Description,Prefix', 'CSV header');
  is_deeply([ map { scalar(() = /,/g) } @lines ], [5, 5, 5], 'six fields on every line');
  like($lines[2], qr/^10\.250\.1\.1,blue,/, 'CSV row carries the VRF');

  SKIP: {
    skip 'xt/snapshots is not shipped in the distribution', 2 unless -d 'xt/snapshots';
    foreach my $pair (['ajax/device/addresses.tt', $html], ['ajax/device/addresses_csv.tt', $csv]) {
      my ($view, $got) = @$pair;
      my $path = snapshot_path($view) =~ s/\.html\z/.two-domains.html/r;
      if ($ENV{ND_WRITE_DOMAIN_SNAPSHOTS}) {
        open my $fh, '>:encoding(UTF-8)', $path or die "$path: $!";
        print {$fh} $got;
        close $fh;
      }
      open my $fh, '<:encoding(UTF-8)', $path or do { fail("$path is missing"); next };
      my $want = do { local $/; <$fh> };
      is($got, $want, "$view matches $path");
    }
  }
};

subtest 'addresses_templates__vrf_name__escaped' => sub {
  my $rows = address_rows('', '<b>R&D</b>');
  my ($html) = render_template('ajax/device/addresses.tt', addresses_stash($rows));
  unlike($html, qr/<b>R&D/, 'no raw markup in the page');
  like($html, qr/\\u003cb>R&D/, 'the data block escapes <');
};

subtest 'addresses_controller__shapes_rows_by_vrf' => sub {
  my $src = do { local (@ARGV, $/) = 'lib/App/Netdisco/Web/Plugin/Device/Addresses.pm'; <> };
  like($src, qr/results_span_domains\(\\\@results\)/, 'decides the column from the rows');
  like($src, qr/label_rows_by_domain\(\\\@results, \$multi_domain\)/, 'labels or drops vrf');
  my $passes = () = $src =~ /multi_domain => \$multi_domain/g;
  is($passes, 2, 'both templates get the flag');
};

# Node search: each node_ip row is one router's record, so it is labeled with
# the local VRF name beside "via <router>". The API serializes search result
# sets with hri, so the domain travels as two flat SQL columns.
my $DEFAULT_ROW_GUARD = qr/CASE WHEN (\w+)\.vrf = '' THEN 0 ELSE l3_domain_of\(\1\.\w+, \1\.vrf\) END/;

sub iterator { my @rows = @_; return { next => sub { shift @rows } } }

sub node_ip_row {
  my %args = @_;
  my %row = (ip => $args{ip} || '10.250.1.50', active => 1, dns => 'host50',
             router_ip => '10.0.0.11', router_name => 'leaf01', nbname => '',
             net_mac => { as_ieee => '00:1c:73:aa:00:01' }, manufacturer => {},
             ip_aliases => sub { $args{aliases} || [] }, node_sightings => sub { [] },
             netbios => [], nodeips => []);
  $row{vrf} = $args{vrf} if exists $args{vrf};
  return \%row;
}

sub node_search_html {
  my ($view, @rows) = @_;
  my %stash = (mac_format_call => 'as_ieee', params => {}, settings => {},
               archive_filter => {}, search_node => '/search?tab=node',
               search_device => '/search?tab=device');
  if ($view =~ /by_ip/) { $stash{macs} = iterator(@rows) }
  else { $stash{ips} = iterator(@rows); $stash{$_} = iterator() for qw/sightings ports wireless netbios/ }
  my ($html, $error) = render_template("ajax/search/$view.tt", \%stash);
  is($error, undef, "$view renders");
  return $html // '';
}

subtest 'node_ip_with_l3_domain__sql__guarded_and_named' => sub {
  my $schema = App::Netdisco::DB->connect('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  my $rs = $schema->resultset('NodeIp')
    ->search_by_ip({ ip => NetAddr::IP::Lite->new('10.0.0.1') })
    ->with_router->with_l3_domain;
  my ($sql) = @{ ${ $rs->as_query } };
  like($sql, qr/CASE WHEN me\.vrf = '' THEN 0 ELSE l3_domain_of\(me\.router_last, me\.vrf\) END,/,
    'domain id, without a function call for default rows');
  like($sql, qr/\(SELECT ld\.name FROM l3_domain ld WHERE ld\.id = CASE WHEN me\.vrf = '' THEN 0 ELSE l3_domain_of\(me\.router_last, me\.vrf\) END\)/,
    'domain name looked up by that id');
  # hri names its keys from the resolved "as" list, not from SQL aliases
  my @as = @{ $rs->_resolved_attrs->{as} };
  is_deeply([ @as[-2, -1] ], [qw/l3_domain_id l3_domain_name/], 'serialized as l3_domain_id and l3_domain_name');
  my $calls = () = $sql =~ /l3_domain_of\(/g;
  my $guarded = () = $sql =~ /$DEFAULT_ROW_GUARD/g;
  is($guarded, $calls, 'every call is in the ELSE of vrf = \'\'');
};

subtest 'node_search__every_node_ip_set__has_l3_domain' => sub {
  my $src = do { local (@ARGV, $/) = 'lib/App/Netdisco/Web/Plugin/Search/Node.pm'; <> };
  my $router = () = $src =~ /->with_router\b/g;
  my $domain = () = $src =~ /->with_router->with_l3_domain\b/g;
  cmp_ok($router, '>', 0, 'node search reads node_ip with its router');
  is($domain, $router, 'and every such set carries its domain');
};

subtest 'node_search_templates__default_rows__render_as_before' => sub {
  foreach my $view (qw/node_by_ip node_by_mac/) {
    my $with = node_search_html($view, node_ip_row(vrf => '', aliases => [node_ip_row(ip => '10.250.1.51', vrf => '')]));
    my $without = node_search_html($view, node_ip_row(aliases => [node_ip_row(ip => '10.250.1.51')]));
    is($with, $without, "$view: a default-table row renders as a row without vrf");
    unlike($with, qr/in VRF/, "$view: no VRF label");
  }
};

subtest 'node_search_templates__named_vrf__labels_local_vrf' => sub {
  foreach my $view (qw/node_by_ip node_by_mac/) {
    my $html = node_search_html($view, node_ip_row(vrf => 'blue'));
    like($html, qr/\(host50\)\s*in VRF blue\s*via/, "$view: label after the name, before via");
    my $escaped = node_search_html($view, node_ip_row(vrf => '<b>R&D</b>'));
    like($escaped, qr/in VRF &lt;b&gt;R&amp;D&lt;\/b&gt;/, "$view: the VRF name is escaped");
  }
  my $alias = node_search_html('node_by_ip',
    node_ip_row(vrf => '', aliases => [node_ip_row(ip => '10.250.1.51', vrf => 'red')]));
  like($alias, qr/10\.250\.1\.51<\/a>.*?in VRF red/s, 'node_by_ip labels a MAC\'s other addresses too');
};

# Ports tab connected nodes: each node IP is labeled with its local VRF, like
# the "(on vlan N)" note beside a node whose VLAN differs from the port's.
sub port_nodes_html {
  my @ips = @_;
  my $node = { active => 1, vlan => 10, net_mac => { as_ieee => '00:1c:73:aa:00:01' },
               stitched_ips => \@ips, wireless => [] };
  my ($html, $error) = render_template('ajax/device/port_nodes.tt', {
    row => { vlan => 10, stitched_nodes => [ $node ] },
    params => { n_ip4 => 1, n_ip6 => 1, n_dns => 1 }, settings => { devport_ips_collapse_threshold => 10 },
    mac_format_call => 'as_ieee', search_node => '/search?tab=node',
  });
  is($error, undef, 'port_nodes renders');
  return $html // '';
}

subtest 'port_nodes__default_rows__render_as_before' => sub {
  my $with = port_nodes_html({ ip => '10.250.1.50', dns => 'host50', active => 1, vrf => '' },
                             { ip => '10.250.1.51', active => 1, vrf => '' });
  my $without = port_nodes_html({ ip => '10.250.1.50', dns => 'host50', active => 1 },
                                { ip => '10.250.1.51', active => 1 });
  is($with, $without, 'a default-table IP renders as an IP without vrf');
  unlike($with, qr/in VRF/, 'no VRF label');
};

subtest 'port_nodes__named_vrf__labels_each_ip' => sub {
  my $html = port_nodes_html({ ip => '10.250.1.50', dns => 'host50', active => 1, vrf => 'blue' },
                             { ip => '10.250.1.51', active => 1, vrf => '<b>R&D</b>' });
  like($html, qr/\(10\.250\.1\.50\)<\/a>\s*in VRF blue/, 'label after the IP shown with its name');
  like($html, qr/10\.250\.1\.51<\/a>\s*in VRF &lt;b&gt;R&amp;D&lt;\/b&gt;/, 'label after a bare IP, escaped');
};

done_testing;
