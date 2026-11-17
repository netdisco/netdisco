#!/usr/bin/env perl

# netdisco-db-deploy refuses a PostgreSQL older than the floor. The check had
# no test; #1833 raises the floor to 10 for SP-GiST inet indexes. This reads
# the source because the script connects to a database when run.

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile updir/;
use FindBin;
use Text::Balanced 'extract_bracketed';

my $script = $ENV{ND_DB_DEPLOY_SCRIPT}
  // catfile($FindBin::Bin, updir(), 'bin', 'netdisco-db-deploy');
open my $fh, '<', $script or die "cannot read $script: $!";
my $source = do { local $/; <$fh> };
close $fh;

my $body;
if ($source =~ /^\s*sub\s+postgres_too_old\s*(?=\{)/mg) {
  ($body) = extract_bracketed(substr($source, pos($source)), '{}');
}
my $loaded = defined $body
  && eval "package DbDeployUnderTest; sub postgres_too_old $body; 1";
diag $@ if defined $body and not $loaded;

sub too_old { return DbDeployUnderTest::postgres_too_old(@_) }

subtest 'postgres_too_old__9_6__refuses' => sub {
  ok($loaded, 'bin/netdisco-db-deploy defines sub postgres_too_old') or return;
  ok(too_old(90624));
};

subtest 'postgres_too_old__just_below_10__refuses' => sub {
  ok($loaded, 'bin/netdisco-db-deploy defines sub postgres_too_old') or return;
  ok(too_old(99999));
};

subtest 'postgres_too_old__10__accepts' => sub {
  ok($loaded, 'bin/netdisco-db-deploy defines sub postgres_too_old') or return;
  ok(!too_old(100000));
};

subtest 'postgres_too_old__18__accepts' => sub {
  ok($loaded, 'bin/netdisco-db-deploy defines sub postgres_too_old') or return;
  ok(!too_old(180001));
};

# a server version the driver could not read is not refused, as before
subtest 'postgres_too_old__unknown__accepts' => sub {
  ok($loaded, 'bin/netdisco-db-deploy defines sub postgres_too_old') or return;
  ok(!too_old(undef));
  ok(!too_old(0));
};

subtest 'db_deploy__message__names_10' => sub {
  like($source, qr/minimum PostgreSQL version for Netdisco is 10, you have/);
  like($source, qr/if \(postgres_too_old\(\$pg_ver\)\)/);
};

done_testing;
