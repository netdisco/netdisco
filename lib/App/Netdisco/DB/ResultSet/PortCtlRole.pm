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
    return $self->distinct('name')->get_column('name')->all;
}

sub device_acls {
    my $self = shift;
    return $self->distinct('device_acl_id')->get_column('device_acl_id')->all;
}

sub port_acls {
    my $self = shift;
    return $self->distinct('port_acl_id')->get_column('port_acl_id')->all;
}

1;