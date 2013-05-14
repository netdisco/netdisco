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
  my ($self, $table, $mode, $sub, @rest) = @_;
  my $sql_fmt = q{LOCK TABLE %s IN %%s MODE};

  return unless $table;
  $table = [$table] if ref '' eq ref $table;
  my $table_fmt = join ', ', ('%s' x scalar @$table);
  my $sql = sprintf $sql_fmt, $table_fmt;

  if (!length $mode) {
      unshift @rest, $sub if $sub;
      $sub = $mode;
      $mode = 'ACCESS EXCLUSIVE';
  }

  $self->txn_do(sub {
      my @params = map {$self->storage->dbh->quote_identifier($_)} @$table;
      $self->storage->dbh->do(sprintf $sql, @params, $mode);
      $sub->(@rest);
  });
}

1;
