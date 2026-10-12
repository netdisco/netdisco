#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Snapshot qw/render_template/;
use App::Netdisco::Util::Statistics 'postgres_version';

my %display_for_server_version = (
    90624  => '9.6.24',
    90600  => '9.6.0',
    100023 => '10.23',
    140000 => '14.0',
    140011 => '14.11',
    180006 => '18.6',
);
foreach my $server_version (sort { $a <=> $b } keys %display_for_server_version) {
    my $display = $display_for_server_version{$server_version};
    subtest "postgresVersion__server_version_${server_version}__reads_${display}" => sub {
        is postgres_version($server_version), $display, 'major.minor from 10, major.minor.patch before';
    };
}

subtest 'postgresVersion__not_a_number__returns_undef' => sub {
    is postgres_version(undef), undef, 'undef';
    is postgres_version('18.6'), undef, 'already formatted';
};

# Rows written before postgres_version() existed hold pretty_version(..., 2)
# output, such as "14.00.11", so the template must read both forms.
sub postgres_cell {
    my $pg_ver = shift;
    my ($html, $error) = render_template('ajax/statistics.tt', {
        stats => { day => '2026-10-11', pg_ver => $pg_ver },
    });
    die "statistics.tt did not render: $error" if defined $error;
    my ($cell) = $html =~ m{postgresql\.org[^>]*>PostgreSQL</a></th>\s*<th>(.*?)</th>}s;
    die "no PostgreSQL row in statistics.tt output" unless defined $cell;
    return $cell;
}

foreach my $pg_ver ('9.3.18', '9.6.24', '10.00.23', '13.00.14', '10.23', '13.14') {
    subtest "statisticsTemplate__postgres_${pg_ver}_below_the_14_floor__is_shown_in_red" => sub {
        like postgres_cell($pg_ver),
          qr{^<span class="badge alert-danger">\Q$pg_ver\E</span>$},
          'version is wrapped in the danger badge';
    };
}

foreach my $pg_ver ('14.00.11', '14.00.00', '18.00.6', '14.0', '18.6') {
    subtest "statisticsTemplate__postgres_${pg_ver}_at_or_above_14__is_shown_plain" => sub {
        is postgres_cell($pg_ver), $pg_ver, 'version has no badge';
    };
}

subtest 'statisticsTemplate__postgres_version_missing__is_shown_without_an_empty_badge' => sub {
    is postgres_cell(undef), '', 'nothing is shown';
};

done_testing;
