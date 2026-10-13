#!/usr/bin/env perl

# The job log's device filter compares me.device alone, so PostgreSQL can use
# the admin(device) index. These assert the generated SQL; no database needed.

use strict;
use warnings;

use Test::More 0.88;
use App::Netdisco::DB;
use App::Netdisco::JobQueue::PostgreSQL ();

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $s = App::Netdisco::DB->clone;
  $s->storage_type('::DBI::Pg');
  $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $s;
};

sub jq_log_sql {
  my %param = @_;
  my $captured;
  no warnings 'redefine';
  local *App::Netdisco::JobQueue::PostgreSQL::param = sub { $param{ $_[0] } };
  local *App::Netdisco::JobQueue::PostgreSQL::vars = sub { {} };
  local *App::Netdisco::JobQueue::PostgreSQL::setting = sub { undef };
  local *App::Netdisco::JobQueue::PostgreSQL::schema = sub { $schema };
  local *DBIx::Class::ResultSet::all = sub { $captured = ${ $_[0]->as_query }; () };
  App::Netdisco::JobQueue::PostgreSQL::jq_log();
  my ($sql, @bind) = @$captured;
  return ($sql, [ map { ref $_ ? $_->[1] : $_ } @bind ]);
}

subtest 'jq_log__device_param__filters_on_admin_device_only' => sub {
  my ($sql, $bind) = jq_log_sql(device => '192.0.2.1');
  like($sql, qr/me\.device = \?/, 'compares me.device');
  unlike($sql, qr/target\.ip = \?/, 'does not also compare the joined device');
  is(scalar(grep { defined && $_ eq '192.0.2.1' } @$bind), 1, 'the device is bound once');
};

subtest 'jq_log__no_device_param__has_no_device_filter' => sub {
  my ($sql) = jq_log_sql();
  unlike($sql, qr/me\.device = \?/, 'no device comparison without the parameter');
};

done_testing;
