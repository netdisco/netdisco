#!/usr/bin/env perl

# Schema 101 drops indexes that another index or the primary key already covers
# and adds four that existing queries lack.

use strict;
use warnings;

use Test::More 0.88;
use DBIx::Class::Schema::Versioned;

my $DIR       = 'share/schema_versions';
my $MIGRATION = "$DIR/App-Netdisco-DB-100-101-PostgreSQL.sql";

my @DROPS = qw(
  node_ip_idx_ip_active idx_node_ip_ip idx_node_ip_mac idx_node_mac
  idx_node_switch idx_node_switch_port idx_device_port_ip idx_device_ip_ip
  idx_node_nbt_mac idx_device_port_wireless_ip_port
);

my @CREATES = (
  'idx_device_port_properties_ip_port ON device_port_properties (ip, port)',
  'idx_node_nbt_ip ON node_nbt (ip)',
  'idx_admin_device ON admin (device)',
  'idx_node_oui ON node (oui)',
);

ok(-f $MIGRATION, "$MIGRATION exists") or BAIL_OUT('migration file missing');

sub normalise {
  my $s = shift;
  $s =~ s/\s+/ /g;
  $s =~ s/^ | $//g;
  return $s;
}

sub raw_lines {
  open my $fh, '<', $MIGRATION or die "$MIGRATION: $!";
  my @lines = <$fh>;
  close $fh;
  chomp @lines;
  return @lines;
}

# every index name an earlier migration creates, ignoring commented-out lines
sub earlier_index_names {
  my %seen;
  for my $file (glob "$DIR/App-Netdisco-DB-*-PostgreSQL.sql") {
    next if $file eq $MIGRATION;
    open my $fh, '<', $file or die "$file: $!";
    while (my $line = <$fh>) {
      next if $line =~ /^\s*--/;
      while ($line =~ /\bINDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)\s+ON\b/gi) {
        $seen{lc $1} = $file;
      }
    }
    close $fh;
  }
  return \%seen;
}

my @statements = grep { /\S/ } map { normalise($_) }
  @{ DBIx::Class::Schema::Versioned->_read_sql_file($MIGRATION) };

subtest 'schema_101__parsed_by_dbic__yields_exactly_the_planned_statements' => sub {
  my @expected = (
    (map { "DROP INDEX IF EXISTS $_" } @DROPS),
    (map { "CREATE INDEX IF NOT EXISTS $_" } @CREATES),
  );
  is_deeply(\@statements, \@expected, 'ten drops then four creates, in order')
    or diag explain \@statements;
};

subtest 'schema_101__every_drop__uses_if_exists' => sub {
  my @drops = grep { /^DROP INDEX/ } @statements;
  is(scalar @drops, scalar @DROPS, 'one drop per planned index');
  is(scalar(grep { !/^DROP INDEX IF EXISTS / } @drops), 0, 'every drop is guarded by IF EXISTS');
};

subtest 'schema_101__every_create__uses_if_not_exists' => sub {
  my @creates = grep { /^CREATE/ } @statements;
  is(scalar @creates, scalar @CREATES, 'one create per planned index');
  is(scalar(grep { !/^CREATE INDEX IF NOT EXISTS / } @creates), 0, 'every create is guarded by IF NOT EXISTS');
};

subtest 'schema_101__file__has_no_trailing_comments_bodies_or_concurrently' => sub {
  my @lines = raw_lines();
  # _read_sql_file drops a comment only when "--" is the first thing on the line
  is_deeply([ grep { /--/ && !/^--/ } @lines ], [], 'every comment starts in column one');
  is_deeply([ grep { /\$\$/ } @lines ], [], 'no dollar-quoted bodies');
  is_deeply([ grep { /CONCURRENTLY/i } @lines ], [], 'no CONCURRENTLY, which cannot run in a transaction');
  is_deeply([ grep { /;.*;/ } @lines ], [], 'at most one statement per line');
};

subtest 'schema_101__every_dropped_index__was_created_by_an_earlier_migration' => sub {
  my $earlier = earlier_index_names();
  ok(exists $earlier->{$_}, "$_ was created earlier, so the drop is not a typo") for @DROPS;
};

subtest 'schema_101__new_index_names__collide_with_no_earlier_migration' => sub {
  my $earlier = earlier_index_names();
  for my $create (@CREATES) {
    my ($name) = $create =~ /^(\w+)/;
    ok(!exists $earlier->{$name}, "$name is new")
      or diag "already created in $earlier->{$name}";
  }
};

subtest 'db_pm__version__matches_highest_migration' => sub {
  open my $fh, '<', 'lib/App/Netdisco/DB.pm' or die "DB.pm: $!";
  my ($version) = map { /\$VERSION\s*=\s*(\d+)/ ? $1 : () } <$fh>;
  close $fh;
  my ($highest) = sort { $b <=> $a }
    map { /App-Netdisco-DB-\d+-(\d+)-PostgreSQL\.sql$/ ? $1 : () } glob "$DIR/*.sql";
  is($highest, $version, 'DB.pm declares the schema version the newest migration reaches');
};

done_testing;
