#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Temp qw/tempdir/;
use File::Spec::Functions qw/catfile catdir/;
use lib 'xt/lib';
use Dancer ();
use App::Netdisco::Web::Statistics;
use Test::Netdisco::Snapshot qw/render_template/;

my $home = tempdir(CLEANUP => 1);
local $ENV{NETDISCO_HOME} = $home;
mkdir catdir($home, 'netdisco-mibs') or die $!;
Dancer::Config::setting('mibhome', undef);

sub write_version {
    my ($dir, $value) = @_;
    open my $fh, '>', catfile($dir, 'VERSION') or die $!;
    print {$fh} $value;
    close $fh;
}

is App::Netdisco::Web::Statistics::mib_bundle_version(), undef,
  'missing VERSION is unavailable';
write_version(catdir($home, 'netdisco-mibs'), "4.064\n");
is App::Netdisco::Web::Statistics::mib_bundle_version(), '4.064',
  'reads the default bundle directory';

my $custom = tempdir(CLEANUP => 1);
Dancer::Config::setting('mibhome', $custom);
write_version($custom, " 4.069\r\n");
is App::Netdisco::Web::Statistics::mib_bundle_version(), '4.069',
  'configured mibhome takes precedence and whitespace is trimmed';
foreach my $bad ('', '<script>bad</script>', '4.069 extra') {
    write_version($custom, $bad);
    is App::Netdisco::Web::Statistics::mib_bundle_version(), undef,
      "invalid VERSION '$bad' is unavailable";
}

foreach my $version ('4.064', undef) {
    my ($html, $error) = render_template('ajax/statistics.tt', {
        stats => { day => '2026-10-05', pg_ver => '12.00.17' },
        mib_bundle_version => $version,
    });
    is $error, undef, 'statistics template renders';
    like $html, qr{https://github\.com/netdisco/netdisco-mibs[^>]*>MIB Bundle</a>},
      'bundle label links to the MIB repository';
    like $html, qr{Python</a>.*MIB Bundle</a>}s, 'bundle follows Python';
    my $expected = defined $version ? $version : 'Unknown';
    like $html, qr{<th>\Q$expected\E</th>}, 'version or fallback is displayed';
}

done_testing;
