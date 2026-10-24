package App::Netdisco::DB::Upsert;

use strict;
use warnings;

my $max_bind_parameters = 65535;

# The three timestamp expressions netdisco workers build themselves, see
# App::Netdisco::Worker::Plugin::Discover. Nothing else is ever inlined.
my @allowed_timestamp_literals = (
  qr/\ALOCALTIMESTAMP\z/,
  qr/\Ato_timestamp\([0-9]+(?:\.[0-9]+)?\)::timestamp\z/,
  qr/\A'[0-9][0-9 :.+\-T]*'::timestamp\z/,
);

=head1 NAME

App::Netdisco::DB::Upsert - bulk INSERT ... ON CONFLICT for every result set

=head1 DESCRIPTION

Internal. This interface may change between releases and is not for site-local
plugins.

Table and column names come only from the result source, never from the
caller, and every identifier is quoted. Every value is a bind parameter, with
one exception: a scalar reference is inlined only when it matches one of the
timestamp expressions netdisco itself builds. Any other reference to SQL dies.

=head1 METHODS

=head2 upsert( \@rows, \%options )

Writes each row with one C<INSERT ... ON CONFLICT (primary key) DO UPDATE>,
in batches that stay under the PostgreSQL bind parameter limit. Returns the
number of rows inserted or updated, so a row already holding the same values
counts as zero. Returns 0 and sends nothing for an empty list.

Each row is a hash reference of column to value. Every row must have the same
keys, including every primary key column, and each key must appear once.
Values are undef, a plain scalar, an array reference of plain scalars (for
array columns), or an allowed timestamp literal.

Options:

=over 4

=item C<insert_only>

Columns written on insert and never changed by the update.

=item C<touch>

Columns updated, but left out of the change test, so they change only when
some other column does.

=back

=cut

sub upsert {
  my ($rs, $rows, $options) = @_;
  $rs->throw_exception("upsert: rows must be an array reference of hash references of column to value")
    unless ref $rows eq 'ARRAY';
  $options = _upsert_options($rs, $options);
  return 0 unless scalar @$rows;

  my $source = $rs->result_source;
  my ($table, @key_columns) = _upsert_target($rs, 'upsert');

  my @columns = _upsert_columns($rs, $table, $rows->[0], $options);
  my @sorted  = _upsert_sorted_rows($rs, $table, $rows, \@columns, \@key_columns);

  my $per_batch = int($max_bind_parameters / scalar @columns) || 1;
  my $changed = 0;
  while (my @batch = splice @sorted, 0, $per_batch) {
    $changed += $source->storage->dbh_do(sub {
      my ($sql, @binds) = _upsert_statement($_[1], $table, \@columns,
        \@key_columns, \@batch, $options);
      return 0 + $_[1]->do($sql, undef, @binds);
    });
  }
  return $changed;
}

=head2 remove_unseen( \%scope, \@seen )

Deletes the rows in C<%scope> whose primary key is not in C<@seen>, with one
plain C<DELETE> and returns the number of rows deleted. It does no cascade, and
it refuses the C<Node> and C<DevicePortLog> sources, whose rows are never
deleted by this method.

Call it on a plain C<< resultset('Source') >>. A result set carrying search
conditions, such as C<< $device-E<gt>port_vlans >>, is refused, because only
C<%scope> restricts the C<DELETE>.

C<%scope> maps primary key columns to plain scalars and must be non-empty. When
C<ip> is one of the source's key columns, C<%scope> must include it (for
discover, C<< { ip =E<gt> $device-E<gt>ip } >>). It must leave at least one key
column out, or it would name a single row. C<@seen> holds hash references with
exactly the key columns not in C<%scope>. An empty C<@seen> deletes every row in
the scope, which is right for a complete walk that found nothing.

=cut

sub remove_unseen {
  my ($rs, $scope, $seen) = @_;
  my ($table, @key_columns) = _upsert_target($rs, 'remove_unseen');
  _remove_unseen_refuse_unsafe_target($rs);
  $rs->throw_exception("remove_unseen: scope must be a hash reference of primary key column to value")
    unless ref $scope eq 'HASH';
  $rs->throw_exception("remove_unseen: scope must name at least one key column of '$table' ("
    . join(', ', @key_columns) . "); an empty scope would delete rows beyond the one device or group being refreshed")
    unless scalar keys %$scope;
  $rs->throw_exception("remove_unseen: seen must be an array reference of hash references of the key columns not in scope")
    unless ref $seen eq 'ARRAY';

  my %is_key = map { $_ => 1 } @key_columns;
  foreach my $name (sort keys %$scope) {
    $rs->throw_exception("remove_unseen: scope column '$name' is not a primary key column of '$table'; use only "
      . join(', ', @key_columns))
      unless $is_key{$name};
    $rs->throw_exception("remove_unseen: scope value for '$name' must be a plain scalar, not undef or a reference")
      unless defined $scope->{$name} and not ref $scope->{$name};
  }
  $rs->throw_exception("remove_unseen: scope for '$table' must include 'ip' or the DELETE would remove other devices' rows;"
    . " discover callers must scope by device, for example { ip => \$device->ip }")
    if $is_key{ip} and not exists $scope->{ip};
  my @scoped = grep { exists $scope->{$_} } @key_columns;
  my @rest   = grep { not exists $scope->{$_} } @key_columns;
  $rs->throw_exception("remove_unseen: scope covers the whole key of '$table'; leave at least one of "
    . join(', ', @key_columns) . " out of the scope and pass its values in seen")
    unless @rest;

  my @casts = _remove_unseen_casts($rs, $table, \@rest);
  my @arrays = _remove_unseen_arrays($rs, $seen, \@rest);
  return $rs->result_source->storage->dbh_do(sub {
    my $dbh = $_[1];
    my $quote = sub { $dbh->quote_identifier($_[0]) };
    my $sql = 'DELETE FROM ' . $quote->($table) . ' WHERE '
      . join(' AND ', map { $quote->($_) . ' = ?' } @scoped)
      . ' AND (' . join(', ', map { $quote->($_) } @rest) . ') NOT IN (SELECT * FROM unnest('
      . join(', ', map { "?::$_\[]" } @casts) . '))';
    return 0 + $dbh->do($sql, undef, (map { $scope->{$_} } @scoped), @arrays);
  });
}

sub _remove_unseen_refuse_unsafe_target {
  my $rs = shift;
  my $source_name = $rs->result_source->source_name;
  $rs->throw_exception("remove_unseen: '$source_name' rows are never deleted by this method; remove them with their own delete code")
    if $source_name eq 'Node' or $source_name eq 'DevicePortLog';

  my $where = $rs->{attrs}{where};
  my $has_conditions = ref $where eq 'HASH' ? scalar keys %$where
    : ref $where eq 'ARRAY' ? scalar @$where : defined $where;
  $rs->throw_exception("remove_unseen: this result set carries search conditions, which the DELETE would ignore;"
    . " call remove_unseen on resultset('$source_name') and pass the restriction in the scope, for example { ip => \$device->ip }")
    if $has_conditions;
  return;
}

sub _remove_unseen_casts {
  my ($rs, $table, $columns) = @_;
  my $source = $rs->result_source;
  return map {
    my $type = $source->column_info($_)->{data_type};
    $rs->throw_exception("remove_unseen: column '$_' of '$table' has data type "
      . (defined $type ? "'$type'" : 'undef') . " that cannot be used as a cast; give it a plain data_type in its result class")
      unless defined $type and $type =~ m/\A[a-z][a-z ]*\z/;
    $type;
  } @$columns;
}

sub _remove_unseen_arrays {
  my ($rs, $seen, $columns) = @_;
  my $expected = join ', ', sort @$columns;
  my @arrays = map { [] } @$columns;

  foreach my $index (0 .. $#$seen) {
    my $row = $seen->[$index];
    $rs->throw_exception("remove_unseen: seen row $index is not a hash reference; pass hash references of key column to value")
      unless ref $row eq 'HASH';
    my $actual = join ', ', sort keys %$row;
    $rs->throw_exception("remove_unseen: seen row $index has columns ($actual) but must have exactly ($expected)")
      unless scalar(keys %$row) == scalar(@$columns) and not grep { not exists $row->{$_} } @$columns;

    foreach my $position (0 .. $#$columns) {
      my $name = $columns->[$position];
      $rs->throw_exception("remove_unseen: seen row $index value for '$name' must be a plain scalar, not undef or a reference")
        unless defined $row->{$name} and not ref $row->{$name};
      push @{ $arrays[$position] }, $row->{$name};
    }
  }
  return @arrays;
}

sub _upsert_target {
  my ($rs, $method) = @_;
  my $source = $rs->result_source;
  my $table  = $source->name;
  $rs->throw_exception("$method: result source '" . $source->source_name
    . "' has no plain table name, so $method cannot use it; call $method on a table result set")
    if ref $table or not defined $table or $table !~ m/\A\w+\z/;

  my @key_columns = $source->primary_columns;
  $rs->throw_exception("$method: table '$table' has no primary key to identify rows by")
    unless @key_columns;
  return ($table, @key_columns);
}

sub _upsert_options {
  my ($rs, $options) = @_;
  return { insert_only => [], touch => [] } unless defined $options;
  $rs->throw_exception("upsert: options must be a hash reference; allowed keys are insert_only, touch")
    unless ref $options eq 'HASH';

  foreach my $name (sort keys %$options) {
    $rs->throw_exception("upsert: unknown option '$name'; allowed options are insert_only, touch")
      unless $name eq 'insert_only' or $name eq 'touch';
  }
  my %clean;
  foreach my $name (qw/insert_only touch/) {
    my $list = $options->{$name};
    $list = [] unless defined $list;
    $rs->throw_exception("upsert: option '$name' must be an array reference of column names")
      if ref $list ne 'ARRAY' or grep { not defined $_ or ref $_ } @$list;
    $clean{$name} = $list;
  }
  return \%clean;
}

sub _upsert_columns {
  my ($rs, $table, $first_row, $options) = @_;
  my $source = $rs->result_source;
  $rs->throw_exception("upsert: rows must be hash references of column to value")
    unless ref $first_row eq 'HASH';

  my @columns = sort keys %$first_row;
  foreach my $name (@columns, @{ $options->{insert_only} || [] }, @{ $options->{touch} || [] }) {
    $rs->throw_exception("upsert: no column '$name' in table '$table'; remove it from the rows or options")
      unless defined $name and $source->has_column($name);
  }
  my %in_rows = map { $_ => 1 } @columns;
  foreach my $name (@{ $options->{insert_only} || [] }, @{ $options->{touch} || [] }) {
    $rs->throw_exception("upsert: option column '$name' is not a key of the rows; add it to every row or remove it from the options")
      unless $in_rows{$name};
  }
  return @columns;
}

sub _upsert_sorted_rows {
  my ($rs, $table, $rows, $columns, $key_columns) = @_;
  my $expected = join ', ', @$columns;
  my (%seen, @keyed);

  foreach my $index (0 .. $#$rows) {
    my $row = $rows->[$index];
    $rs->throw_exception("upsert: row $index is not a hash reference; pass hash references of column to value")
      unless ref $row eq 'HASH';

    my $actual = join ', ', sort keys %$row;
    $rs->throw_exception("upsert: row $index has columns ($actual) but row 0 has ($expected); pass rows that all have the same columns")
      unless scalar(keys %$row) == scalar(@$columns) and not grep { not exists $row->{$_} } @$columns;

    foreach my $name (@$key_columns) {
      $rs->throw_exception("upsert: row $index has no value for primary key column '$name' of '$table'; every row must set "
        . join(', ', @$key_columns))
        unless defined $row->{$name} and not ref $row->{$name};
    }
    _upsert_check_value($rs, $_, $row->{$_}) for @$columns;

    my @key_values = map { $row->{$_} } @$key_columns;
    my $joined = join "\0", @key_values;
    $rs->throw_exception("upsert: duplicate key (" . join(', ', @key_values)
      . ") in rows for '$table'; the caller must pass each key once")
      if $seen{$joined}++;
    push @keyed, [$joined, $row];
  }
  return map { $_->[1] } sort { $a->[0] cmp $b->[0] } @keyed;
}

sub _upsert_check_value {
  my ($rs, $name, $value) = @_;
  my $kind = ref $value;
  return if not $kind;

  if ($kind eq 'ARRAY') {
    return unless grep { ref $_ } @$value;
    $rs->throw_exception("upsert: value for '$name' is an array reference with an element that is itself a reference; "
      . "it must be undef, a plain scalar, an array reference of plain scalars, or an allowed timestamp literal");
  }
  elsif ($kind eq 'SCALAR' or $kind eq 'REF') {
    return if $kind eq 'SCALAR' and _upsert_is_timestamp_literal($value);
    my $shown = (($kind eq 'SCALAR') and defined $$value and not ref $$value)
      ? "'$$value'" : '(a reference)';
    $rs->throw_exception("upsert: literal SQL $shown for '$name' is not an allowed timestamp form; "
      . "pass a plain value so it is bound, or LOCALTIMESTAMP, to_timestamp(N)::timestamp or 'YYYY-MM-DD HH:MM:SS'::timestamp");
  }
  $rs->throw_exception("upsert: value for '$name' is a $kind reference, which must be undef, a plain scalar, "
    . "an array reference of plain scalars, or an allowed timestamp literal");
}

sub _upsert_is_timestamp_literal {
  my $text = ${ $_[0] };
  return 0 if not defined $text or ref $text;
  return scalar grep { $text =~ $_ } @allowed_timestamp_literals;
}

sub _upsert_statement {
  my ($dbh, $table, $columns, $key_columns, $batch, $options) = @_;
  my $quote = sub { $dbh->quote_identifier($_[0]) };
  my %skip = map { $_ => 1 } @$key_columns, @{ $options->{insert_only} || [] };
  my %touch = map { $_ => 1 } @{ $options->{touch} || [] };

  my @update = grep { not $skip{$_} } @$columns;
  my @compare = grep { not $touch{$_} } @update;

  my @binds;
  my @tuples = map {
    my $row = $_;
    '(' . join(', ', map {
      my $value = $row->{$_};
      if (ref $value eq 'SCALAR') { $$value }
      else { push @binds, $value; '?' }
    } @$columns) . ')';
  } @$batch;

  my $quoted_table = $quote->($table);
  my $sql = "INSERT INTO $quoted_table (" . join(', ', map { $quote->($_) } @$columns)
    . ') VALUES ' . join(', ', @tuples)
    . ' ON CONFLICT (' . join(', ', map { $quote->($_) } @$key_columns) . ')';

  if (not @compare) {
    return ("$sql DO NOTHING", @binds);
  }
  $sql .= ' DO UPDATE SET '
    . join(', ', map { $quote->($_) . ' = EXCLUDED.' . $quote->($_) } @update)
    . ' WHERE (' . join(', ', map { "$quoted_table." . $quote->($_) } @compare)
    . ') IS DISTINCT FROM (' . join(', ', map { 'EXCLUDED.' . $quote->($_) } @compare) . ')';
  return ($sql, @binds);
}

1;
