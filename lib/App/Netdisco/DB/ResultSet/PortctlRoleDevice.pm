package App::Netdisco::DB::ResultSet::PortctlRoleDevice;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=cut

sub role_can_admin { 
    my ($self, $role) = @_;
    return $self->search({ role => $role })->all;
}



1;