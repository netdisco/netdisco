#!/usr/bin/env perl

# App::Netdisco::DB::StepFile reads a schema step file as SQL, where DBIC's
# _read_sql_file reads it as lines. The two must agree on every shipped file
# (legacy_statements is the fallback for steps below the baseline), and the
# real parser must not break on dollar-quoted bodies the old splitter mangled.

use strict;
use warnings;

use Test::More 0.88;
use Try::Tiny;
use File::Temp ();
use DBIx::Class::Schema::Versioned;

use App::Netdisco::DB::StepFile qw(
  parse_step_file legacy_statements inline_comment_lines step_file_path
);

sub exception (&) { my $code = shift; return try { $code->(); undef } catch { $_ } }

my $FIXTURE_DIR = File::Temp->newdir;
my $fixture_count = 0;

sub write_fixture {
  my $sql = shift;
  my $path = sprintf '%s/fixture-%d.sql', $FIXTURE_DIR->dirname, ++$fixture_count;
  open my $fh, '>', $path or die "$path: $!";
  print $fh $sql;
  close $fh;
  return $path;
}

sub shipped_step_files {
  return sort { step_from($a) <=> step_from($b) }
    glob 'share/schema_versions/App-Netdisco-DB-*-*-PostgreSQL.sql';
}

sub step_from {
  my $file = shift;
  return ($file =~ m{App-Netdisco-DB-(\d+)-\d+-PostgreSQL\.sql$})[0];
}

subtest 'parse_step_file__begin_commit_wrappers__are_dropped' => sub {
  my $p = parse_step_file(write_fixture("BEGIN;\nCREATE TABLE a (x int);\nCOMMIT;\n"));
  is_deeply($p->{statements}, ['CREATE TABLE a (x int)']);
  is($p->{no_transaction}, 0);
};
subtest 'parse_step_file__dollar_quoted_body__keeps_one_statement' => sub {
  my $sql = "DO \$\$ BEGIN IF true THEN RAISE NOTICE 'a; b'; END IF; END \$\$;\nSELECT 1;\n";
  is(scalar @{ parse_step_file(write_fixture($sql))->{statements} }, 2);
};
subtest 'parse_step_file__tagged_dollar_quote__keeps_one_statement' => sub {
  my $sql = "CREATE FUNCTION f() RETURNS int AS \$body\$ SELECT 1; \$body\$ LANGUAGE sql;\n";
  is(scalar @{ parse_step_file(write_fixture($sql))->{statements} }, 1);
};
subtest 'parse_step_file__semicolon_in_string__keeps_one_statement' => sub {
  is(scalar @{ parse_step_file(write_fixture("UPDATE t SET a = 'x;y';\n"))->{statements} }, 1);
};
subtest 'parse_step_file__semicolon_in_line_comment__is_not_a_split' => sub {
  is(scalar @{ parse_step_file(write_fixture("-- a; b\nSELECT 1; -- c; d\n"))->{statements} }, 1);
};
subtest 'parse_step_file__no_transaction_directive__is_detected_on_first_line_only' => sub {
  is(parse_step_file(write_fixture("-- netdisco: no-transaction\nSELECT 1;\n"))->{no_transaction}, 1);
  is(parse_step_file(write_fixture("SELECT 1;\n-- netdisco: no-transaction\n"))->{no_transaction}, 0);
};
subtest 'parse_step_file__missing_file__dies_naming_the_path' => sub {
  like(exception { parse_step_file('/nonexistent/x.sql') }, qr{/nonexistent/x\.sql});
};
subtest 'parse_step_file__doubled_quote_in_string__stays_in_string' => sub {
  my $p = parse_step_file(write_fixture("SELECT 'it''s; fine';\nSELECT 2;\n"));
  is_deeply($p->{statements}, ["SELECT 'it''s; fine'", 'SELECT 2']);
};
subtest 'parse_step_file__dollar_in_placeholder__is_not_a_quote' => sub {
  is(scalar @{ parse_step_file(write_fixture("SELECT \$1;\nSELECT \$2;\n"))->{statements} }, 2);
};
subtest 'step_file_path__from_version__names_the_next_step' => sub {
  is(step_file_path('/s', 100), '/s/App-Netdisco-DB-100-101-PostgreSQL.sql');
};
subtest 'legacy_statements__every_shipped_step__matches_dbic_read_sql_file' => sub {
  # the tolerant fallback must split exactly as the old runner did
  foreach my $file (shipped_step_files()) {
    is_deeply(legacy_statements($file), DBIx::Class::Schema::Versioned->_read_sql_file($file), $file);
  }
};
subtest 'inline_comment_lines__code_then_comment__reports_line' => sub {
  is_deeply(inline_comment_lines(write_fixture("-- ok\nSELECT 1; -- bad\nSELECT '--';\n")), [2]);
};
subtest 'inline_comment_lines__steps_from_101__have_none' => sub {
  # the old splitter joins lines, so an inline comment swallows the next statement
  my @files = grep { step_from($_) >= 101 } shipped_step_files();
  # until a step from 101 exists, a subtest with no assertions would fail
  pass('no step file from 101 exists yet') unless @files;
  foreach my $file (@files) {
    is_deeply(inline_comment_lines($file), [], $file);
  }
};

done_testing;
