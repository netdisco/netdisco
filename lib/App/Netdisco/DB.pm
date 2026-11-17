use utf8;
package App::Netdisco::DB;

use strict;
use warnings;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces(
    default_resultset_class => 'ResultSet',
);

our # try to hide from kwalitee
  $VERSION = 108; # schema version used for upgrades, keep as integer

use Path::Class;
use File::ShareDir 'dist_dir';

our $schema_versions_dir = Path::Class::Dir->new( dist_dir('App-Netdisco') )
  ->subdir('schema_versions')->stringify;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::SchemaVersioned
  +App::Netdisco::DB::ExplicitLocking
/);

__PACKAGE__->upgrade_directory($schema_versions_dir);

=head1 METHODS

=head2 without_jit( $code )

Runs C<$code> in a transaction with PostgreSQL's JIT compilation off, and
returns what C<$code> returns. For queries whose cost estimate starts JIT
compilation that takes longer than the query itself.

=cut

sub without_jit {
  my ($self, $code) = @_;
  return $self->txn_do(sub {
    my $dbh = $self->storage->dbh;
    # PostgreSQL 10 has no jit setting; drop this check when the floor is 14
    $dbh->do('SET LOCAL jit = off')
      if ($dbh->{pg_server_version} || 0) >= 110000;
    return $code->();
  });
}

1;
