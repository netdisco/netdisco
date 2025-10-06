package App::Netdisco::DB::ResultSet::PortCtlRole;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=cut

sub get_roles  {
    my ($self) = @_;
    return $self->get_column('role_name')->all;
}


1;