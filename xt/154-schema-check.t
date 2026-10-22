#!/usr/bin/env perl

# The pure parts of netdisco-db-deploy --check. Building the scratch install
# and reading the catalogs needs PostgreSQL, so that is tested in the database
# harness.

use strict;
use warnings;

use Test::More 0.88;

use App::Netdisco::DB::SchemaCheck qw(
  catalog_sql normalize_lines diff_lines check_privilege_message
  version_mismatch_message
);

subtest 'normalize_lines__scratch_schema_name__becomes_public' => sub {
  is_deeply(normalize_lines(['index i CREATE INDEX i ON ndcheck_1.node USING btree (mac)'], 'ndcheck_1'),
    ['index i CREATE INDEX i ON public.node USING btree (mac)']);
};
subtest 'normalize_lines__function_definition__schema_stripped_before_hashing' => sub {
  my ($scratch) = @{ normalize_lines(['function port_sortkey(raw text) CREATE OR REPLACE FUNCTION ndcheck_1.port_sortkey(raw text) RETURNS text'], 'ndcheck_1') };
  my ($public) = @{ normalize_lines(['function port_sortkey(raw text) CREATE OR REPLACE FUNCTION public.port_sortkey(raw text) RETURNS text'], 'public') };
  is($scratch, $public);
  unlike($scratch, qr/CREATE OR REPLACE/, 'definition hashed');
};
subtest 'diff_lines__both_sides__reports_each_direction' => sub {
  is_deeply(diff_lines([qw/a b/], [qw/b c/]), { only_here => ['a'], only_fresh => ['c'] });
};
subtest 'diff_lines__identical__empty' => sub {
  is_deeply(diff_lines([qw/a/], [qw/a/]), { only_here => [], only_fresh => [] });
};
subtest 'check_privilege_message__names_database__gives_both_fixes' => sub {
  my $m = check_privilege_message('ndprod', 'ndrole');
  like($m, qr/ALTER DATABASE ndprod OWNER TO ndrole;/);
  like($m, qr/GRANT CREATE ON DATABASE ndprod TO ndrole;/);
};
subtest 'catalog_sql__schema_name__is_a_placeholder_not_interpolated' => sub {
  unlike(catalog_sql(), qr/'public'/);
  like(catalog_sql(), qr/\?/);
};

subtest 'normalize_lines__quoted_schema_name__becomes_public' => sub {
  is_deeply(normalize_lines(['constraint a.b FOREIGN KEY (ip) REFERENCES "ndcheck_1".device(ip)'], 'ndcheck_1'),
    ['constraint a.b FOREIGN KEY (ip) REFERENCES public.device(ip)']);
};
subtest 'normalize_lines__longer_name_sharing_the_prefix__left_alone' => sub {
  is_deeply(normalize_lines(['index i ON ndcheck_12.node'], 'ndcheck_1'), ['index i ON ndcheck_12.node']);
};
subtest 'normalize_lines__multiline_function__one_line_named_by_its_signature' => sub {
  my ($line) = @{ normalize_lines(["function f(a integer) CREATE OR REPLACE FUNCTION ndcheck_1.f(a integer)\n RETURNS integer\nAS \$\$ select ndcheck_1.g(a) \$\$\n"], 'ndcheck_1') };
  like($line, qr/\Afunction f\(a integer\) [0-9a-f]{32}\z/);
};
subtest 'normalize_lines__view_definition__hashed_after_schema_stripped' => sub {
  my ($scratch) = @{ normalize_lines(["view v  SELECT ip\n   FROM ndcheck_1.device;"], 'ndcheck_1') };
  my ($public) = @{ normalize_lines(["view v  SELECT ip\n   FROM public.device;"], 'public') };
  is($scratch, $public);
  like($scratch, qr/\Aview v [0-9a-f]{32}\z/);
};
subtest 'catalog_sql__not_null_constraints__left_to_the_column_line' => sub {
  like(catalog_sql(), qr/con\.contype <> 'n'/);
};
subtest 'normalize_lines__pre_10_default_expansions__read_as_the_value_function' => sub {
  my %expanded = (
    q{('now'::text)::date} => 'CURRENT_DATE',
    q{('now'::text)::time with time zone} => 'CURRENT_TIME',
    q{('now'::text)::time without time zone} => 'LOCALTIME',
    q{('now'::text)::timestamp without time zone} => 'LOCALTIMESTAMP',
    q{now()} => 'CURRENT_TIMESTAMP',
  );
  for my $old (sort keys %expanded) {
    is_deeply(normalize_lines(["column t.c date not null default $old"], 'public'),
      normalize_lines(["column t.c date not null default $expanded{$old}"], 'public'), $old);
  }
};
subtest 'normalize_lines__expansion_outside_a_default__left_alone' => sub {
  my $line = q{index i CREATE INDEX i ON public.t USING btree (c) WHERE (c < ('now'::text)::date)};
  is_deeply(normalize_lines([$line], 'public'), [$line]);
};
subtest 'catalog_sql__placeholders__one_per_schema_reference' => sub {
  my $placeholders = () = catalog_sql() =~ m/\?/g;
  is($placeholders, 2, 'relations and functions each bind the schema name');
};

subtest 'version_mismatch_message__database_behind__asks_for_the_upgrade' => sub {
  my $m = version_mismatch_message(98, 102);
  like($m, qr/schema version 98 and this Netdisco expects 102/);
  like($m, qr/Run netdisco-db-deploy to upgrade it/);
};
subtest 'version_mismatch_message__unversioned_database__says_none' => sub {
  like(version_mismatch_message(0, 102), qr/schema version none .*Run netdisco-db-deploy/);
};
subtest 'version_mismatch_message__database_ahead__points_at_the_newer_netdisco' => sub {
  my $m = version_mismatch_message(103, 102);
  like($m, qr/newer than this Netdisco/);
  unlike($m, qr/Run netdisco-db-deploy/);
};
# A stand-in schema for run_check's version gate. Its dbh refuses CREATE
# SCHEMA, so a call that passes the gate stops at the scratch schema with a
# message of its own.
{
  package Local::GateDbh;
  sub new { bless {}, shift }
  sub selectrow_hashref { return { schema_name => 'public', database => 'nd', role => 'nd', can_create => 1 } }
  sub quote_identifier { return qq{"$_[1]"} }
  sub do { die "stand-in refuses $_[1]\n" }
  package Local::GateSchema;
  sub new { my ($class, %arg) = @_; bless { %arg, dbh => Local::GateDbh->new }, $class }
  sub storage { return $_[0] }
  sub dbh { return $_[0]{dbh} }
  sub get_db_version { return $_[0]{db_version} }
  sub schema_version { return $_[0]{schema_version} }
}

sub run_gate {
  my ($db_version, $schema_version) = @_;
  my $err = '';
  open my $err_handle, '>', \$err or die $!;
  local *STDERR = $err_handle;
  my $code = App::Netdisco::DB::SchemaCheck::run_check(
    Local::GateSchema->new(db_version => $db_version, schema_version => $schema_version));
  return ($code, $err);
}

subtest 'run_check__database_behind__exits_2_asking_for_the_upgrade' => sub {
  my ($code, $err) = run_gate(101, 102);
  is($code, 2);
  like($err, qr/schema version 101 and this Netdisco expects 102/);
  like($err, qr/Run netdisco-db-deploy to upgrade it/);
};
subtest 'run_check__database_ahead__exits_2_naming_the_newer_netdisco' => sub {
  my ($code, $err) = run_gate(103, 102);
  is($code, 2);
  like($err, qr/newer than this Netdisco/);
  unlike($err, qr/temporary schema/, 'stops before the scratch schema');
};
subtest 'run_check__same_version__passes_the_gate' => sub {
  my ($code, $err) = run_gate(102, 102);
  like($err, qr/creating the temporary schema "ndcheck_\d+" failed/, 'reaches the scratch schema');
  unlike($err, qr/this Netdisco/, 'no version message');
};
done_testing;
