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
done_testing;
