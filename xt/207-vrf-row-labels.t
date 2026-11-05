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

done_testing;
