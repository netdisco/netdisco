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

done_testing;
