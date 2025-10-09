package App::Netdisco::DB::ResultSet::PortCtlRoleDevicePort;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=cut

sub get_acls {
  my ($self, $role) = @_;
  return $self->search({ role_name => $role })->all;
}

1;