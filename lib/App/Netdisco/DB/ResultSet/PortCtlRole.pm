package App::Netdisco::DB::ResultSet::PortCtlRole;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=cut

sub role_names  {
    my $self = shift;
    return $self->get_column('name')->all;
}


1;