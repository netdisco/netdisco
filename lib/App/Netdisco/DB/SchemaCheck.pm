package App::Netdisco::DB::SchemaCheck;

use strict;
use warnings;

use Try::Tiny;
use Digest::MD5 'md5_hex';
use Encode 'encode_utf8';

use App::Netdisco::DB;
use App::Netdisco::DB::Deploy 'run_deploy';

use base 'Exporter';
our @EXPORT_OK = qw(
  catalog_sql normalize_lines diff_lines check_privilege_message
  version_mismatch_message run_check
);

# One line per object in the bound schema; written for 9.6 and later, so no
# prokind (11+). Extensions are database-wide, so both sides list the same.
# PostgreSQL 18 names NOT NULL constraints after the column at creation, so a
# renamed column's name depends on history; the column line carries nullability.
my $CATALOG_SQL = <<'EOF';
WITH rel AS (
  SELECT c.oid, c.relname, c.relkind FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = ?
)
SELECT line FROM (
  SELECT 'table ' || relname AS line FROM rel WHERE relkind IN ('r', 'p')
  UNION ALL
  SELECT 'column ' || r.relname || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
    || CASE WHEN a.attnotnull THEN ' not null' ELSE ' null' END
    || ' default ' || coalesce(pg_get_expr(d.adbin, d.adrelid), 'none')
    FROM rel r JOIN pg_attribute a ON a.attrelid = r.oid
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE r.relkind IN ('r', 'p') AND a.attnum > 0 AND NOT a.attisdropped
  UNION ALL
  SELECT 'index ' || ic.relname || ' ' || pg_get_indexdef(i.indexrelid)
    FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid JOIN rel t ON t.oid = i.indrelid
  UNION ALL
  SELECT 'constraint ' || t.relname || '.' || con.conname || ' ' || pg_get_constraintdef(con.oid)
    FROM pg_constraint con JOIN rel t ON t.oid = con.conrelid WHERE con.contype <> 'n'
  UNION ALL
  SELECT 'sequence ' || relname FROM rel WHERE relkind = 'S'
  UNION ALL
  SELECT 'view ' || relname || ' ' || pg_get_viewdef(oid) FROM rel WHERE relkind IN ('v', 'm')
  UNION ALL
  SELECT 'function ' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ') '
    || pg_get_functiondef(p.oid)
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = ? AND NOT EXISTS (SELECT 1 FROM pg_aggregate g WHERE g.aggfnoid = p.oid)
  UNION ALL
  SELECT 'extension ' || extname FROM pg_extension
) lines ORDER BY line COLLATE "C"
EOF

sub catalog_sql { return $CATALOG_SQL }

sub _hash_definition {
  my $line = shift;
  return "$1 " . md5_hex(encode_utf8($2))
    if $line =~ m/\A(function .+?\)) (CREATE\b.*)\z/s
    or $line =~ m/\A(view \S+) (.*)\z/s;
  return $line;
}

# Before PostgreSQL 10 these defaults were stored expanded, and a dump restore
# keeps the expansion, so a database first built on 9.x reads differently.
my %VALUE_FUNCTION = (
  q{('now'::text)::date} => 'CURRENT_DATE',
  q{('now'::text)::time with time zone} => 'CURRENT_TIME',
  q{('now'::text)::time without time zone} => 'LOCALTIME',
  q{('now'::text)::timestamp without time zone} => 'LOCALTIMESTAMP',
  q{now()} => 'CURRENT_TIMESTAMP',
);

sub _value_function_default {
  my $line = shift;
  return $line unless $line =~ m/\A(column .+? default )(.+)\z/s;
  return $1 . ($VALUE_FUNCTION{$2} // $2);
}

sub normalize_lines {
  my ($lines, $schema_name) = @_;
  my $qualified = qr/(?<![\w"])(?:\Q$schema_name\E|"\Q$schema_name\E")\./;
  return [ map { _hash_definition(_value_function_default(s/$qualified/public./gr)) } @$lines ];
}

sub diff_lines {
  my ($here, $fresh) = @_;
  my %in_here = map { $_ => 1 } @$here;
  my %in_fresh = map { $_ => 1 } @$fresh;
  return {
    only_here => [ grep { not $in_fresh{$_} } @$here ],
    only_fresh => [ grep { not $in_here{$_} } @$fresh ],
  };
}

sub check_privilege_message {
  my ($database, $role) = @_;
  return "Cannot check the schema: --check builds a fresh install in a temporary"
    . " schema to compare with, which needs the CREATE privilege on database"
    . " $database, and role $role does not have it. Nothing was changed. As a"
    . " PostgreSQL superuser, run one of these, then run the check again:\n"
    . "  ALTER DATABASE $database OWNER TO $role;\n"
    . "  GRANT CREATE ON DATABASE $database TO $role;\n"
    . "The first matches a documented install, where Netdisco's role owns its database.";
}

# A fresh install is built at the code's version, so against a database at
# another version every pending step would read as drift.
sub version_mismatch_message {
  my ($db_version, $target_version) = @_;
  my $action = $db_version > $target_version
    ? "This database is newer than this Netdisco: run the check with the Netdisco version that upgraded it."
    : "Run netdisco-db-deploy to upgrade it, then run the check again.";
  return "Cannot check the schema: this database is at schema version "
    . ($db_version || 'none') . " and this Netdisco expects $target_version."
    . " A comparison would mix drift with steps not yet applied, so none was"
    . " made and nothing was changed. $action";
}

sub _read_catalog {
  my ($dbh, $schema_name) = @_;
  my $lines = $dbh->selectcol_arrayref(catalog_sql(), undef, $schema_name, $schema_name);
  return normalize_lines($lines, $schema_name);
}

sub _scratch_connect_info {
  my ($schema, $quoted_scratch) = @_;
  my @info = @{ $schema->storage->connect_info };
  my %attributes = (ref $info[-1] eq 'HASH') ? %{ pop @info } : ();
  my $existing = $attributes{on_connect_do};
  $attributes{on_connect_do} = [
    (ref $existing eq 'ARRAY' ? @$existing : defined $existing ? ($existing) : ()),
    "SET search_path TO $quoted_scratch",
    'SET client_min_messages TO warning',
  ];
  $attributes{ignore_version} = 1;
  return (@info, \%attributes);
}

# Deploy prints its failure advice for a real upgrade, so it is captured and
# shown only when the reference install fails.
sub _deploy_reference {
  my $scratch_schema = shift;
  my ($exit_code, $captured) = (2, '');
  {
    local *STDERR;
    open STDERR, '>', \$captured or die "cannot capture the reference install's output: $!\n";
    $exit_code = try { run_deploy($scratch_schema, { quiet => 1 }) }
      catch { print STDERR $_; 2 };
  }
  return 1 if $exit_code == 0;
  print STDERR "Cannot check the schema: the fresh reference install, built in a"
    . " temporary schema, did not complete, so no comparison was made. This"
    . " database was not changed; ignore any advice below about forcing a step,"
    . " which concerns the temporary copy. Please report this as a Netdisco bug."
    . " The reference install reported:\n", $captured;
  return 0;
}

sub _fresh_catalog {
  my ($schema, $scratch_name, $quoted_scratch) = @_;
  my $scratch_schema = App::Netdisco::DB->connect(
    _scratch_connect_info($schema, $quoted_scratch));
  return try {
    _deploy_reference($scratch_schema)
      ? _read_catalog($scratch_schema->storage->dbh, $scratch_name) : undef;
  }
  catch { print STDERR "Cannot check the schema: $_"; undef }
  finally { $scratch_schema->storage->disconnect };
}

sub _drop_scratch {
  my ($schema, $quoted_scratch) = @_;
  try {
    $schema->txn_do(sub {
      my $dbh = $schema->storage->dbh;
      $dbh->do('SET LOCAL client_min_messages TO warning');
      $dbh->do("DROP SCHEMA $quoted_scratch CASCADE");
    });
  }
  catch {
    print STDERR "Could not drop the temporary schema $quoted_scratch: $_"
      . "Drop it by hand with: DROP SCHEMA $quoted_scratch CASCADE;\n";
  };
}

sub _report_differences {
  my ($schema, $differences) = @_;
  print "only in this database: $_\n" for @{ $differences->{only_here} };
  print "only in a fresh install: $_\n" for @{ $differences->{only_fresh} };

  my $count = @{ $differences->{only_here} } + @{ $differences->{only_fresh} };
  my $target_version = $schema->schema_version;
  my $noun = $count == 1 ? 'difference' : 'differences';
  print(($count || 'No') . " $noun from a fresh install of schema version $target_version.\n");
  return $count ? 1 : 0;
}

sub _session_facts {
  my $dbh = shift;
  return $dbh->selectrow_hashref(q{SELECT current_schema() AS schema_name,
    current_database() AS database, current_user AS role,
    has_database_privilege(current_user, current_database(), 'CREATE') AS can_create});
}

sub _create_scratch {
  my ($dbh, $quoted_scratch) = @_;
  return try { $dbh->do("CREATE SCHEMA $quoted_scratch"); 1 }
  catch {
    print STDERR "Cannot check the schema: creating the temporary schema"
      . " $quoted_scratch failed, so nothing was changed: $_";
    0;
  };
}

sub run_check {
  my $schema = shift;
  my $dbh = $schema->storage->dbh;
  my $facts = _session_facts($dbh);
  if (not defined $facts->{schema_name}) {
    print STDERR "Cannot check the schema: no schema on the search_path exists in database $facts->{database}.\n";
    return 2;
  }
  if (not $facts->{can_create}) {
    print STDERR check_privilege_message($facts->{database}, $facts->{role}), "\n";
    return 2;
  }
  my ($db_version, $target_version) = ($schema->get_db_version, $schema->schema_version);
  if ($db_version != $target_version) {
    print STDERR version_mismatch_message($db_version, $target_version), "\n";
    return 2;
  }

  my $scratch_name = "ndcheck_$$";
  my $quoted_scratch = $dbh->quote_identifier($scratch_name);
  return 2 unless _create_scratch($dbh, $quoted_scratch);

  my $fresh_lines = try { _fresh_catalog($schema, $scratch_name, $quoted_scratch) }
    catch { print STDERR "Cannot check the schema: $_"; undef }
    finally { _drop_scratch($schema, $quoted_scratch) };
  return 2 unless $fresh_lines;

  my $here_lines = _read_catalog($dbh, $facts->{schema_name});
  return _report_differences($schema, diff_lines($here_lines, $fresh_lines));
}

1;
