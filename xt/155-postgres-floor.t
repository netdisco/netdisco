use strict;
use warnings;

# nothing listens on port 1, so the live lookup fails fast and no test needs
# a database
BEGIN {
  $ENV{DANCER_ENVDIR} = '/dev/null';
  $ENV{PGHOST} = '127.0.0.1';
  $ENV{PGPORT} = 1;
}

use Test::More 0.88;
use Scalar::Util 'refaddr';
use App::Netdisco;
use Dancer ':script';
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::PostgresFloor
  qw/$POSTGRES_FLOOR_MAJOR postgres_floor_warning warn_postgres_floor_all_tenants/;

subtest 'postgres_floor_warning__below_14__names_version_and_tenant' => sub {
  my $w = postgres_floor_warning(130012, 'netdisco');
  like($w, qr/13\.12/); like($w, qr/\b14\b/); like($w, qr/netdisco/);
  like($w, qr{https://github\.com/netdisco/netdisco/wiki/Release-Notes});
  like($w, qr/future release/);
};
subtest 'postgres_floor_warning__14_and_above__undef' => sub {
  is(postgres_floor_warning(140000, 'x'), undef);
  is(postgres_floor_warning(180006, 'x'), undef);
};
subtest 'postgres_floor_warning__9_6__formats_three_part' => sub {
  like(postgres_floor_warning(90624, 'x'), qr/9\.6\.24/);
};
subtest 'postgres_floor_warning__garbage__undef' => sub {
  is(postgres_floor_warning(undef, 'x'), undef);
  is(postgres_floor_warning('abc', 'x'), undef);
};
subtest 'postgres_floor_warning__numeric_junk_below_9_0__undef' => sub {
  is(postgres_floor_warning($_, 'x'), undef) for 0, 13, 1000, 89999;
};
subtest 'postgres_floor_warning__tenant_label__is_named' => sub {
  like(postgres_floor_warning(130012, 'east'), qr/database "east"/);
};
subtest 'POSTGRES_FLOOR_MAJOR__is_14' => sub {
  is($POSTGRES_FLOOR_MAJOR, 14);
};
subtest 'warn_postgres_floor_all_tenants__fake_versions__logs_each_old_one' => sub {
  my %version_for = (netdisco => 130012, east => 180006, west => 90624, down => undef);
  my @logged;
  warn_postgres_floor_all_tenants(sub { push @logged, shift },
    { labels => [ sort keys %version_for ],
      version_for => sub { $version_for{shift()} } });
  is(scalar @logged, 2, 'only the old databases log');
  like($logged[0], qr/"netdisco"/); like($logged[1], qr/"west"/);
};
subtest 'warn_postgres_floor_all_tenants__lookup_dies__stays_silent' => sub {
  my @logged;
  warn_postgres_floor_all_tenants(sub { push @logged, shift },
    { labels => ['netdisco'], version_for => sub { die "no database\n" } });
  is(scalar @logged, 0);
};
# the backend runs this in its master process, before forking pollers. a
# schema cached there under 'netdisco' leaves each poller a second schema,
# for 'default', with its own connection; discover then locked device_port
# on one and waited on that lock from the other
subtest 'warn_postgres_floor_all_tenants__live_lookup__leaves_one_schema_per_process' => sub {
  set logger => 'null';
  warn_postgres_floor_all_tenants(sub {});
  is(refaddr(schema(undef)), refaddr(schema('netdisco')), "schema(undef) is schema('netdisco')");
};
done_testing;
