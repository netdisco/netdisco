package App::Netdisco::DB::ResultSet::AccessControlListMap;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=cut

sub acl_names  {
    my $self = shift;
    return $self->distinct('acl_name')->order_by('acl_name')->get_column('acl_name')->all;
}

sub left_acls {
    my $self = shift;
    return $self->distinct('left_acl_id')->get_column('left_acl_id')->all;
}

sub right_acls {
    my $self = shift;
    return $self->distinct('right_acl_id')->get_column('right_acl_id')->all;
}

1;