#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

# metrics_job_duration_per_device: the most recent finished job per device and
# action, as two series carrying its status. Asked for because the job queue
# keeps only expire_jobs days and can be cleared by hand, which loses the one
# record of whether a device's macsuck was failing last week; scraped, the
# history stays in the metrics store.
#
# Three claims, kept apart:
#   - the view picks the latest finished job whatever its status, so a failing
#     macsuck after a good one shows as the failure (SQL shape offline, rows
#     against a database when one is reachable, inside a rolled back
#     transaction);
#   - the series are off by default, because they are one per device and
#     action;
#   - switched on, the endpoint emits them;
#   - metrics_per_device_only and _no limit them to some devices, matched on
#     the device row, so a property works as well as an address.

my $envdir;
BEGIN {
  # As xt/94: the app refuses to build without a public directory, and the
  # route registers at load time only if metrics_path comes from a file.
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');
  $envdir = File::Temp->newdir(CLEANUP => 1);
  open my $env, '>', catfile("$envdir", 'testing.yml')
    or die "cannot write the test environment file: $!";
  print $env "metrics_path: '/xt-metrics'\n";
  close $env;
  $ENV{DANCER_ENVDIR} = "$envdir";
  $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;

my $psgi = catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg');
my $app  = eval { Plack::Util::load_psgi($psgi) };
BAIL_OUT("could not load $psgi: $@") unless $app;

# As xt/94, Dancer's keywords are not imported here.
sub setting { return Dancer::Config::setting(@_) }

# Loaded after the app, so it does not read the configuration before the
# environment file above is in place.
require App::Netdisco::DB;

my $offline = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $s = App::Netdisco::DB->clone;
  $s->storage_type('::DBI::Pg');
  $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $s;
};

subtest 'deviceLastJobs__sql__latest_finished_job_per_device_and_action' => sub {
  my ($sql, @bind) = @{ ${ $offline->resultset('Virtual::DeviceLastJobs')
    ->search({ action => { -in => [qw/discover macsuck/] } })->as_query } };

  like $sql, qr/SELECT DISTINCT ON \(device, action\)/, 'one row per device and action';
  like $sql, qr/ORDER BY device, action, started DESC/, 'the most recent one';
  like $sql, qr/finished IS NOT NULL/, 'only finished jobs, so running ones have no duration yet';
  unlike $sql, qr/status\s*=/, 'any status, so a failure is not skipped for an older success';
  is_deeply [ map { $_->[1] } @bind ], [qw/discover macsuck/], 'actions are bound, not interpolated';
};

test_psgi $app, sub {
  my $cb = shift;
  setting('metrics_allow' => []);
  setting('metrics_token' => '');

  my $body = $cb->(GET '/xt-metrics')->content;
  unlike $body, qr/netdisco_device_last_job_/,
    'metricsDeviceLastJobs__shipped_default__emits_nothing';

  setting('metrics_job_duration_per_device' => 1);
  $body = $cb->(GET '/xt-metrics')->content;
  like $body, qr/^# TYPE netdisco_device_last_job_timestamp_seconds gauge$/m,
    'metricsDeviceLastJobs__switched_on__emits_the_start_time';
  like $body, qr/^# TYPE netdisco_device_last_job_duration_seconds gauge$/m,
    'metricsDeviceLastJobs__switched_on__emits_the_duration';
  setting('metrics_job_duration_per_device' => 0);
};

# The app is loaded by now, so its schema is used as is; a `use Dancer` block
# here would run at compile time, before the environment file is read.
my $schema = eval {
  my $s = Dancer::Plugin::DBIC::schema('netdisco');
  $s->storage->dbh_do(sub { $_[1]->do('SELECT 1') });
  $s;
};
my $why = $@;

SKIP: {
  skip "no usable netdisco database: $why", 7 if not $schema;

  # 192.0.2.0/24 is documentation space, so no real device is touched, and
  # the transaction is rolled back whatever happens.
  my %got;
  eval {
    $schema->txn_do(sub {
      my $admin = $schema->resultset('Admin');
      my $ago = sub { \[ q{LOCALTIMESTAMP - ?::interval}, $_[0] ] };
      $admin->create({ device => '192.0.2.1', action => 'macsuck', status => 'done',
        started => $ago->('3 hours'), finished => $ago->('179 minutes') });
      $admin->create({ device => '192.0.2.1', action => 'macsuck', status => 'error',
        started => $ago->('1 hour'), finished => $ago->('59 minutes') });
      $admin->create({ device => '192.0.2.1', action => 'macsuck', status => 'queued',
        started => $ago->('1 minute') });
      $admin->create({ device => '192.0.2.1', action => 'discover', status => 'done',
        started => $ago->('2 hours'), finished => $ago->('119 minutes') });

      $got{$_->{action}} = $_ for $schema->resultset('Virtual::DeviceLastJobs')
        ->search({ device => '192.0.2.1' })->hri->all;

      # The endpoint, on the same handle so it sees these rows, under the
      # per-device ACLs. They match the device row, which is made here too.
      $schema->resultset('Device')->create({ ip => '192.0.2.1', vendor => 'xtvendor' });
      my $series = qr/^netdisco_device_last_job_timestamp_seconds\{action="macsuck",device="192\.0\.2\.1",status="error",tenant="netdisco"\} \d+$/m;
      test_psgi $app, sub {
        my $cb = shift;
        setting('metrics_job_duration_per_device' => 1);
        my $acl = sub {
          setting('metrics_per_device_only' => $_[0]);
          setting('metrics_per_device_no' => $_[1]);
          return $cb->(GET '/xt-metrics')->content;
        };
        $got{endpoint}{none}  = $acl->([], []) =~ $series;
        $got{endpoint}{only}  = $acl->(['192.0.2.0/24'], []) =~ $series;
        $got{endpoint}{other} = $acl->(['198.51.100.0/24'], []) =~ $series;
        $got{endpoint}{no}    = $acl->([], ['vendor:xtvendor']) =~ $series;
        $acl->([], []);
        setting('metrics_job_duration_per_device' => 0);
      };
      die "rollback\n";
    });
  };
  die $@ if $@ and $@ !~ /rollback/;

  is $got{macsuck}{status}, 'error',
    'deviceLastJobs__rows__a_newer_failure_wins_over_an_older_success';
  cmp_ok abs($got{macsuck}{duration} - 60), '<', 1,
    'deviceLastJobs__rows__the_running_job_is_left_out';
  is $got{discover}{status}, 'done',
    'deviceLastJobs__rows__each_action_on_its_own';

  ok $got{endpoint}{none}, 'metricsPerDeviceAcl__none_set__every_device';
  ok $got{endpoint}{only}, 'metricsPerDeviceAcl__only_matching__kept';
  ok !$got{endpoint}{other}, 'metricsPerDeviceAcl__only_not_matching__left_out';
  ok !$got{endpoint}{no}, 'metricsPerDeviceAcl__no_on_a_property__left_out';
}

done_testing;
