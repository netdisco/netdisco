#!/usr/bin/env perl

# step_mode picks the path each schema step runs on: strict from the baseline
# on, tolerant below it and for --redeploy-all, forced only for the one step
# named by --force-step. The database paths themselves are tested in the
# database harness, since xt stays free of PostgreSQL.

use strict;
use warnings;

use Test::More 0.88;
use File::Temp ();

use App::Netdisco::DB::SchemaVersioned;
use App::Netdisco::DB::StepFile qw(parse_step_file step_file_path);

*step_mode = \&App::Netdisco::DB::SchemaVersioned::step_mode;

subtest 'baseline__is_version_38' => sub {
  is($App::Netdisco::DB::SchemaVersioned::BASELINE, 38);
};
subtest 'step_mode__below_baseline__tolerant' => sub {
  is(step_mode(1, {}), 'tolerant'); is(step_mode(37, {}), 'tolerant');
};
subtest 'step_mode__baseline_and_above__strict' => sub {
  is(step_mode(38, {}), 'strict'); is(step_mode(101, {}), 'strict');
};
subtest 'step_mode__redeploy_all__tolerant_everywhere' => sub {
  is(step_mode(90, { redeploy_all => 1 }), 'tolerant');
};
subtest 'step_mode__force_step__forced_for_that_step_only' => sub {
  is(step_mode(57, { force_step => 57 }), 'forced');
  is(step_mode(58, { force_step => 57 }), 'strict');
};
subtest 'step_mode__no_options__strict_at_baseline' => sub {
  is(step_mode(38), 'strict');
};

my $share = 'share/schema_versions';
sub squash { my $sql = lc shift; $sql =~ s/\s+//g; return $sql }
sub step_statements { return parse_step_file(step_file_path($share, shift))->{statements} }
sub has_statement {
  my ($wanted, $statements) = @_;
  return scalar grep { squash($_) eq squash($wanted) } @$statements;
}

subtest 'step_101__schema_step_forced_ddl__matches_runner' => sub {
  ok(has_statement($App::Netdisco::DB::SchemaVersioned::SCHEMA_STEP_FORCED_DDL, step_statements(101)), 'same definition');
};
subtest 'step_101__port_sortkey__matches_98_99_body' => sub {
  my ($want) = grep { m/port_sortkey/ } @{ step_statements(98) };
  ok($want, 'found the 98-99 function');
  ok(has_statement($want, step_statements(101)), 'same function');
};
subtest 'step_101__index_repair__has_11_drops_23_creates_and_spares_mac_ip' => sub {
  my @statements = @{ step_statements(101) };
  is(scalar(grep { /^DROP INDEX IF EXISTS /i } @statements), 11);
  is(scalar(grep { /^CREATE INDEX IF NOT EXISTS idx_/i } @statements), 23);
  ok(!(grep { /device_port_idx_mac_ip/ } @statements), 'hand-made index untouched');
};
subtest 'step_101__ssid_repair__reuses_the_57_58_deletes_and_key' => sub {
  my @guard = grep { /device_port_ssid/ } @{ step_statements(57) };
  my @deletes = grep { /^DELETE FROM device_port_ssid/i } @guard;
  is(scalar @deletes, 2);
  my @repair = @{ step_statements(101) };
  my $position_of = sub {
    my $wanted = shift;
    my ($index) = grep { squash($repair[$_]) eq squash($wanted) } 0 .. $#repair;
    ok(defined $index, 'present: ' . substr($wanted, 0, 60));
    return $index // -1;
  };
  my @delete_positions = map { $position_of->($_) } @deletes;
  my @not_null_positions = map {
    $position_of->("ALTER TABLE device_port_ssid ALTER COLUMN $_ SET NOT NULL")
  } qw(ip port bssid);
  my $drop_position = $position_of->('ALTER TABLE device_port_ssid DROP CONSTRAINT IF EXISTS device_port_ssid_pkey');
  my ($key) = grep { /ADD CONSTRAINT device_port_ssid_pkey/ } @guard;
  my $add_position = $position_of->($key);
  cmp_ok($delete_positions[$_], '<', $not_null_positions[0], 'delete before SET NOT NULL') for 0, 1;
  cmp_ok($delete_positions[1], '>', $delete_positions[0], 'null cleanup before duplicate cleanup');
  cmp_ok($not_null_positions[2], '<', $drop_position, 'SET NOT NULL before key drop');
  cmp_ok($drop_position, '<', $add_position, 'DROP CONSTRAINT before ADD');
};
subtest 'step_101__device_route__is_one_guarded_do_block' => sub {
  my @blocks = grep { /to_regclass\('device_route'\)/ } @{ step_statements(101) };
  is(scalar @blocks, 1);
  like($blocks[0], qr/IF to_regclass.*IF EXISTS \(SELECT 1 FROM device_route\).*RAISE NOTICE.*ELSE\s+DROP TABLE device_route/s);
};
# an unscoped lookup sees the live tables while --check builds its scratch
# install in another schema of the same database
sub lookups_scoped {
  my $block = shift;
  my $lookups = () = $block =~ /information_schema\.\w+\b/g;
  my $scoped = () = $block =~ /information_schema\.\w+ WHERE table_schema = current_schema\(\)/g;
  return $lookups > 0 && $lookups == $scoped && $block !~ /pg_catalog|to_regclass/;
}
subtest 'step_32_and_93__replay_leftover__created_only_without_the_renamed_object' => sub {
  my %guard = (32 => qr/'snmp_auth_tag', 'snmp_auth_tag_read'.*ADD COLUMN snmp_auth_tag text/s,
    93 => qr/'portctl_role', 'access_control_list_map'.*CREATE TABLE portctl_role/s);
  foreach my $step (sort keys %guard) {
    my @blocks = grep { /^DO / && $_ =~ $guard{$step} } @{ step_statements($step) };
    is(scalar @blocks, 1, "step $step has one guarded block");
    ok(lookups_scoped($blocks[0] // ''), "step $step scopes every lookup");
  }
};
# a 2.008000 install already has jobs_queued at schema 20; without IF NOT
# EXISTS the whole-file attempt fails and the old splitter breaks the DO block
subtest 'step_20__jobs_queued__skips_an_existing_index_and_duplicate_jobs' => sub {
  my @blocks = grep { /jobs_queued/ } @{ step_statements(20) };
  is(scalar @blocks, 1, 'one statement');
  like($blocks[0] // '', qr/^DO .*CREATE UNIQUE INDEX IF NOT EXISTS jobs_queued .*EXCEPTION WHEN unique_violation THEN\s+NULL;/s);
};
# a replay over an existing access_control_list must run the file whole, so
# the portctl_role guard decides, not the old splitter breaking the DO block
subtest 'step_93__access_control_list__created_only_if_missing' => sub {
  my @creates = grep { /CREATE TABLE\b.*\baccess_control_list\b/ } @{ step_statements(93) };
  is(scalar @creates, 1, 'one statement');
  like($creates[0] // '', qr/^CREATE TABLE IF NOT EXISTS access_control_list \(/);
};
subtest 'step_101__replay_leftovers__dropped_only_when_empty_else_noticed' => sub {
  # no CASCADE: a site's own view or key on a leftover stops the upgrade
  # instead of being dropped with it
  my %drop = ('community.snmp_auth_tag' => 'ALTER TABLE community DROP COLUMN snmp_auth_tag;',
    portctl_role => 'DROP TABLE portctl_role;');
  my %successor = ('community.snmp_auth_tag' => 'snmp_auth_tag_read', portctl_role => 'access_control_list_map');
  my @statements = @{ step_statements(101) };
  my $position_of = sub { my $wanted = shift; my ($index) = grep { $statements[$_] =~ $wanted } 0 .. $#statements; return $index // -1 };
  my $notice = $position_of->(qr/^SET LOCAL client_min_messages = notice/);
  my ($warning) = grep { $_ > $notice && $statements[$_] =~ /^SET LOCAL client_min_messages = warning/ } 0 .. $#statements;
  foreach my $leftover (sort keys %drop) {
    my @blocks = grep { /\Q$drop{$leftover}\E/ } @statements;
    is(scalar @blocks, 1, "one block drops $leftover");
    my $kept = qr/RAISE NOTICE '\Q$leftover\E kept: [^']+';/;
    like($blocks[0] // '', qr/IF NOT EXISTS \(SELECT 1 FROM information_schema\.\w+ WHERE .*?'\Q$successor{$leftover}\E'\)\s+THEN\s+$kept\s+ELSIF EXISTS \(SELECT 1 FROM \w+(?: WHERE \w+ IS NOT NULL)?\)\s+THEN\s+$kept\s+ELSE\s+\Q$drop{$leftover}\E/s,
      "$leftover kept with a NOTICE unless $successor{$leftover} exists and it is empty");
    ok(lookups_scoped($blocks[0] // ''), "$leftover lookups scoped");
    my $drop_position = $position_of->(qr/\Q$drop{$leftover}\E/);
    ok($notice >= 0 && $notice < $drop_position && $drop_position < ($warning // -1), "$leftover NOTICE section reaches the client");
  }
};
# Pinning the list makes a new guard fail here until it is added, rather than
# go unchecked.
subtest 'every_step_file__information_schema_lookups__scoped_to_current_schema' => sub {
  my @found;
  foreach my $file (sort glob "$share/*-PostgreSQL.sql") {
    open my $fh, '<', $file or die "cannot read $file: $!";
    next unless do { local $/; <$fh> } =~ /information_schema/;
    my ($from) = $file =~ /-DB-(\d+)-\d+-PostgreSQL\.sql\z/;
    push @found, $from;
    my @blocks = grep { /information_schema/ } @{ parse_step_file($file)->{statements} };
    ok(scalar @blocks, "step $from has a statement with a lookup");
    ok(lookups_scoped($_), "step $from: " . substr($_ =~ s/\s+/ /gr, 0, 60)) for @blocks;
  }
  is_deeply([sort { $a <=> $b } @found], [32, 50, 52, 55, 58, 64, 66, 93, 101], 'step files with lookups');
};
subtest 'schema_version__is_104' => sub {
  open my $fh, '<', 'lib/App/Netdisco/DB.pm' or die "cannot read DB.pm: $!";
  my ($declared) = map { /\$VERSION = (\d+);/ ? $1 : () } <$fh>;
  is($declared, 104);
};

# A stand-in storage that refuses CONCURRENTLY inside a transaction, as
# PostgreSQL does with SQLSTATE 25001, so the runner's transaction handling
# can be tested without a database. It also refuses, with 42601, the pieces
# that the old splitter cuts a DO block into.
{
  package StandInDbh;
  sub new { bless { in_transaction => 0, ran => [] }, shift }
  sub state { $_[0]{state} }
  sub errstr { $_[0]{errstr} }
  sub selectrow_array { 'notice' }
  sub quote { "'$_[1]'" }
  sub do {
    my ($self, $sql) = @_;
    push @{ $self->{ran} }, [$sql, $self->{in_transaction}];
    my ($state, $error) =
        ($sql =~ /CONCURRENTLY/ and $self->{in_transaction})
          ? ('25001', 'cannot run inside a transaction block')
      : $sql =~ /existing_idx/ ? ('42P07', 'relation already exists')
      : ((() = $sql =~ /\$\$/g) % 2 or $sql =~ /^\s*END\b/)
          ? ('42601', 'syntax error')
      : ();
    ($self->{state}, $self->{errstr}) = ($state, $error);
    die "$error\n" if $state;
    return 1;
  }

  package StandInStorage;
  sub new { bless { dbh => StandInDbh->new }, shift }
  sub dbh { $_[0]{dbh} }
  sub sqlt_type { 'PostgreSQL' }
  sub txn_do {
    my ($self, $code) = @_;
    local $self->{dbh}{in_transaction} = 1;
    return $code->();
  }

  package StandInSchema;
  our @ISA = ('App::Netdisco::DB::SchemaVersioned');
  sub new { bless { storage => StandInStorage->new }, shift }
  sub storage { $_[0]{storage} }
  sub _set_db_version { 1 }

  package ForcingStandInSchema;
  our @ISA = ('StandInSchema');
  sub new { my ($class, $file) = @_; my $self = StandInSchema::new($class); $self->{file} = $file; $self }
  sub ddl_filename { $_[0]{file} }
  sub upgrade_directory { '' }
  sub record_forced_step { my ($self, $from, $skipped) = @_; $self->{forced} = [$from, $skipped] }
}

sub step_file_with {
  my $sql = shift;
  my $fh = File::Temp->new(SUFFIX => '.sql');
  print {$fh} $sql;
  close $fh;
  return $fh;
}

subtest 'tolerant_step__no_transaction_file__fallback_runs_outside_transactions' => sub {
  my $file = step_file_with("-- netdisco: no-transaction\n"
    . "CREATE INDEX CONCURRENTLY existing_idx ON device (ip);\n"
    . "CREATE INDEX CONCURRENTLY new_idx ON device (dns);\n");
  my $schema = StandInSchema->new;
  my $result = $schema->_tolerant_step("$file", 2);
  my @ran = @{ $schema->storage->dbh->{ran} };
  is($result->{expected}, 1, 'existing index tolerated');
  is_deeply($result->{unexpected}, [], 'nothing refused for running in a transaction');
  is(scalar(grep { $_->[0] =~ /CONCURRENTLY/ and $_->[1] } @ran), 0, 'no CONCURRENTLY inside a transaction');
  is(scalar(grep { $_->[0] =~ /new_idx/ } @ran), 1, 'new index created once');
};
subtest 'strict_step__transactional_file__quiets_notices_first_in_the_transaction' => sub {
  my $file = step_file_with("CREATE TABLE IF NOT EXISTS t (a integer);\n");
  my $schema = StandInSchema->new;
  ok($schema->_strict_step("$file", 2)->{ok});
  is_deeply($schema->storage->dbh->{ran}[0], ['SET LOCAL client_min_messages = warning', 1]);
};
subtest 'strict_step__no_transaction_file__quiets_the_session_then_restores_it' => sub {
  my $file = step_file_with("-- netdisco: no-transaction\nCREATE INDEX CONCURRENTLY new_idx ON device (dns);\n");
  my $schema = StandInSchema->new;
  ok($schema->_strict_step("$file", 2)->{ok});
  my @settings = map { $_->[0] } grep { $_->[0] =~ /client_min_messages/ } @{ $schema->storage->dbh->{ran} };
  is_deeply(\@settings, ['SET client_min_messages = warning', "SET client_min_messages = 'notice'"]);
};

my $do_block = "DO \$\$\nBEGIN\n  IF NOT EXISTS (SELECT 1 FROM t) THEN\n"
  . "    ALTER TABLE device ADD COLUMN foo text;\n  END IF;\nEND\$\$;\n";
my $forced_sql = "CREATE INDEX existing_idx ON device (ip);\n$do_block";
sub forced_run {
  my ($from, $mode) = @_;
  my $file = step_file_with($forced_sql);
  my $schema = ForcingStandInSchema->new("$file");
  $schema->upgrade_single_step($from, $from + 1, $mode);
  my @replayed = map { $_->[0] } grep { $_->[0] !~ /client_min_messages/ } @{ $schema->storage->dbh->{ran} };
  # the whole-file attempt stops at the first statement
  return ($schema, [ @replayed[1 .. $#replayed] ]);
}
subtest 'upgrade_single_step__forced_at_baseline__replays_do_block_whole_and_records_only_the_failure' => sub {
  my ($schema, $replayed) = forced_run(102, 'forced');
  is(scalar @$replayed, 2, 'two statements replayed');
  like($replayed->[1], qr/\ADO \$\$.*ADD COLUMN foo text;.*END\$\$\z/s, 'DO block replayed as one statement');
  is($schema->{forced}[0], 102, 'forced step recorded');
  is_deeply([map { $_->{statement} } @{ $schema->{forced}[1] }],
    ['CREATE INDEX existing_idx ON device (ip)'], 'only the failing statement recorded');
};
subtest 'upgrade_single_step__forced_step_that_applies_cleanly__records_nothing' => sub {
  my $file = step_file_with("CREATE TABLE IF NOT EXISTS t (a integer);\n");
  my $schema = ForcingStandInSchema->new("$file");
  my $result = $schema->upgrade_single_step(102, 103, 'forced');
  ok($result->{ok}, 'applied');
  is_deeply($result->{skipped}, [], 'nothing skipped');
  ok(!exists $schema->{forced}, 'no schema_step_forced row');
};
subtest 'upgrade_single_step__forced_below_baseline__replays_with_the_old_splitter' => sub {
  my ($schema, $replayed) = forced_run(37, 'forced');
  is(scalar @$replayed, 4, 'DO block cut into fragments as before');
  is(scalar @{ $schema->{forced}[1] }, 4, 'failing statement and three fragments recorded');
};
subtest 'upgrade_single_step__tolerant_at_baseline__replays_with_the_old_splitter' => sub {
  my ($schema, $replayed) = forced_run(90, 'tolerant');
  is(scalar @$replayed, 4, 'redeploy-all replay noise unchanged');
  ok(!exists $schema->{forced}, 'nothing recorded');
};

done_testing;
