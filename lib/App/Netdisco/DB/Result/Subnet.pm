use utf8;
package App::Netdisco::DB::Result::Subnet;


use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
use App::Netdisco::Util::L3Domain 'row_l3_domain';
__PACKAGE__->table("subnets");
__PACKAGE__->add_columns(
  "net",
  { data_type => "cidr", is_nullable => 0 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "last_discover",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "vrf",
  { data_type => "text", is_nullable => 0, default_value => "" },
  "router_last",
  { data_type => "inet", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("net", "vrf");


=head2 l3_domain

Returns C<< { id, name } >> of the L3 domain this row's VRF belongs to, or undef
when it cannot be determined. A default-table row is domain 0 without a query.

=cut

sub l3_domain { return row_l3_domain($_[0], ($_[0]->has_column_loaded('router_last') ? $_[0]->get_column('router_last') : undef)) }

sub TO_JSON {
  my $self = shift;
  my $data = $self->next::method(@_);
  $data->{l3_domain} = $self->l3_domain;
  return $data;
}

1;
