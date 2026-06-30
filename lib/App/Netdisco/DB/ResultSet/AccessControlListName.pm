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

sub host_acl_names  {
    my $self = shift;
    return $self->search({acl_type => 'host'})
      ->order_by('acl_name')->get_column('acl_name')->all;
}

sub host_host_acl_names  {
    my $self = shift;
    return $self->search({acl_type => 'host_host'})
      ->order_by('acl_name')->get_column('acl_name')->all;
}

sub host_port_acl_names  {
    my $self = shift;
    return $self->search({acl_type => 'host_port'})
      ->order_by('acl_name')->get_column('acl_name')->all;
}

1;