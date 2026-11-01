package App::Netdisco::Util::ManagedConfig;

use strict;
use warnings;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use base 'Exporter';
our @EXPORT_OK = qw/
  tenant_key
  acl_txn_do
  _read_config_version
  _bump_config_version
/;

=head1 NAME

App::Netdisco::Util::ManagedConfig - ACL Manager data loaded into the config

=head1 DESCRIPTION

The C<config_version> table holds one counter per scope. The C<acl> counter
goes up by one every time the ACL Manager writes, so a process can tell
whether its copy is stale with one cheap read.

The counter is bumped in Perl by L</acl_txn_do>, not by a database trigger.
That keeps the bump visible at the place where the ACL is written, and a
reader of the writing code can see which writes are counted.

=head1 EXPORT_OK

=head2 tenant_key

Returns the current tenant, or C<netdisco> for the default tenant.

=cut

sub tenant_key { return (vars->{'tenant'} || 'netdisco') }

=head2 acl_txn_do( $coderef )

Runs C<$coderef> in a transaction on the current tenant's database, then bumps
the C<acl> counter in that same transaction and returns what C<$coderef>
returned. If C<$coderef> dies nothing is bumped and the error propagates.

=cut

sub acl_txn_do {
  my $code = shift;
  my $schema = schema(tenant_key());
  return $schema->txn_do(sub {
    my @ret = wantarray ? $code->() : scalar $code->();
    _bump_config_version($schema);
    return wantarray ? @ret : $ret[0];
  });
}

# Plain DBI rather than a resultset: this read happens on every request, and
# DBIC costs about 1 ms against 0.03 ms. Dies if the table or row is missing
# (database not yet upgraded); the caller decides what that means.
sub _read_config_version {
  my $tenant_key = shift;
  return schema($tenant_key)->storage->dbh_do(sub {
    my ($storage, $dbh, @bind) = @_;
    my ($version) = $dbh->selectrow_array(
      'SELECT version FROM config_version WHERE scope = ?', undef, @bind);
    return $version;
  }, 'acl');
}

sub _bump_config_version {
  my $schema = shift;
  $schema->storage->dbh_do(sub {
    my ($storage, $dbh, @bind) = @_;
    $dbh->do('UPDATE config_version SET version = version + 1 WHERE scope = ?',
      undef, @bind);
  }, 'acl');
  return;
}

1;
