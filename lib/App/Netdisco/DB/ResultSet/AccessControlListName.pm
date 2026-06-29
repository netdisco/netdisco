package App::Netdisco::DB::ResultSet::AccessControlListName;
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
    return $self->order_by('acl_name')->get_column('acl_name')->all;
}

1;