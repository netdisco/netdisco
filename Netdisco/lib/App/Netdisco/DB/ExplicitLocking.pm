package App::Netdisco::DB::ExplicitLocking;

use strict;
use warnings FATAL => 'all';

our %lock_modes;

BEGIN {
  %lock_modes = (
    ACCESS_SHARE => 'ACCESS SHARE',
    ROW_SHARE => 'ROW SHARE',
    ROW_EXCLUSIVE => 'ROW EXCLUSIVE',
    SHARE_UPDATE_EXCLUSIVE => 'SHARE UPDATE EXCLUSIVE',
    SHARE => 'SHARE',
    SHARE_ROW_EXCLUSIVE => 'SHARE ROW EXCLUSIVE',
    EXCLUSIVE => 'EXCLUSIVE',
    ACCESS_EXCLUSIVE => 'ACCESS EXCLUSIVE',
  );
}

use constant \%lock_modes;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = (keys %lock_modes);
our %EXPORT_TAGS = (modes => \@EXPORT_OK);

sub txn_do_locked {
  my ($self, $table, $mode, $sub) = @_;
  my $sql_fmt = q{LOCK TABLE %s IN %%s MODE};
  my $schema = $self;

  if ($self->can('result_source')) {
      # ResultSet component
      $sub = $mode;
      $mode = $table;
      $table = $self->result_source->from;
      $schema = $self->result_source->schema;
  }

  $schema->throw_exception('missing Table name to txn_do_locked()')
    unless $table;

  $table = [$table] if ref '' eq ref $table;
  my $table_fmt = join ', ', ('%s' x scalar @$table);
  my $sql = sprintf $sql_fmt, $table_fmt;

  if (ref '' eq ref $mode and $mode) {
      scalar grep {$_ eq $mode} values %lock_modes
        or $schema->throw_exception('bad LOCK_MODE to txn_do_locked()');
  }
  else {
      $sub = $mode;
      $mode = 'ACCESS EXCLUSIVE';
  }

  $schema->txn_do(sub {
      my @params = map {$schema->storage->dbh->quote_identifier($_)} @$table;
      $schema->storage->dbh->do(sprintf $sql, @params, $mode);
      $sub->();
  });
}

=head1 NAME

App::Netdisco::DB::ExplicitLocking - Support for PostgreSQL Lock Modes

=head1 SYNOPSIS

In your L<DBIx::Class> schema:

 package My::Schema;
 __PACKAGE__->load_components('+App::Netdisco::DB::ExplicitLocking');

Then, in your application code:

 use App::Netdisco::DB::ExplicitLocking ':modes';
 $schema->txn_do_locked($table, MODE_NAME, sub { ... });

This also works for the ResultSet:

 package My::Schema::ResultSet::TableName;
 __PACKAGE__->load_components('+App::Netdisco::DB::ExplicitLocking');

Then, in your application code:

 use App::Netdisco::DB::ExplicitLocking ':modes';
 $schema->resultset('TableName')->txn_do_locked(MODE_NAME, sub { ... });

=head1 DESCRIPTION

This L<DBIx::Class> component provides an easy way to execute PostgreSQL table
locks before a transaction block.

You can load the component in either the Schema class or ResultSet class (or
both) and then use an interface very similar to C<DBIx::Class>'s C<txn_do()>.

The package also exports constants for each of the table lock modes supported
by PostgreSQL, which must be used if specifying the mode (default mode is
C<ACCESS EXCLUSIVE>).

=head1 EXPORTS

With the C<:modes> tag (as in SYNOPSIS above) the following constants are
exported and must be used if specifying the lock mode:

=over 4

=item * C<ACCESS_SHARE>

=item * C<ROW_SHARE>

=item * C<ROW_EXCLUSIVE>

=item * C<SHARE_UPDATE_EXCLUSIVE>

=item * C<SHARE>

=item * C<SHARE_ROW_EXCLUSIVE>

=item * C<EXCLUSIVE>

=item * C<ACCESS_EXCLUSIVE>

=back

=head1 METHODS

=head2 C<< $schema->txn_do_locked($table|\@tables, MODE_NAME?, $subref) >>

This is the method signature used when the component is loaded into your
Schema class. The reason you might want to use this over the ResultSet version
(below) is to specify multiple tables to be locked before the transaction.

The first argument is one or more tables, and is required. Note that these are
the real table names in PostgreSQL, and not C<DBIx::Class> ResultSet aliases
or anything like that.

The mode name is optional, and defaults to C<ACCESS EXCLUSIVE>. You must use
one of the exported constants in this parameter.

Finally pass a subroutine reference, just as you would to the normal
C<DBIx::Class> C<txn_do()> method. Note that additional arguments are not
supported.

=head2 C<< $resultset->txn_do_locked(MODE_NAME?, $subref) >>

This is the method signature used when the component is loaded into your
ResultSet class. If you don't yet have a ResultSet class (which is the default
- normally only Result classes are created) then you can create a stub which
simply loads this component (and inherits from C<DBIx::Class::ResultSet>).

This is the simplest way to use this module if you only want to lock one table
before your transaction block.

The first argument is the optional mode name, which defaults to C<ACCESS
EXCLUSIVE>. You must use one of the exported constants in this parameter.

The second argument is a subroutine reference, just as you would pass to the
normal C<DBIx::Class> C<txn_do()> method. Note that additional arguments are
not supported.

=cut

1;
