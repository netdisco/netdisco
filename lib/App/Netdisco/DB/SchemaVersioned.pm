package App::Netdisco::DB::SchemaVersioned;

use strict;
use warnings;

use base 'DBIx::Class::Schema::Versioned';

use Try::Tiny;
use DBIx::Class::Carp;

sub apply_statement {
    my ($self, $statement) = @_;
    try { $self->storage->txn_do(sub { $self->storage->dbh->do($statement) }) }
    catch { carp "SQL was: $statement" if $ENV{DBIC_TRACE} };
}

1;
