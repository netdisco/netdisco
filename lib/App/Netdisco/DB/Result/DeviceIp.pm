use utf8;
package App::Netdisco::DB::Result::DeviceIp;


use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
use App::Netdisco::Util::L3Domain 'row_l3_domain';

__PACKAGE__->table("device_ip");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "alias",
  { data_type => "inet", is_nullable => 0 },
  "subnet",
  { data_type => "cidr", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 1 },
  "dns",
  { data_type => "text", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "first_seen",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "vrf",
  { data_type => "text", is_nullable => 0, default_value => "" },
);
__PACKAGE__->set_primary_key("ip", "alias", "vrf");



=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table to which this IP alias relates.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 device_port

Returns the Port on which this IP address is configured (typically a loopback,
routed port or virtual interface).

=cut

__PACKAGE__->belongs_to( device_port => 'App::Netdisco::DB::Result::DevicePort',
  { 'foreign.port' => 'self.port', 'foreign.ip' => 'self.ip' } );


=head2 l3_domain

Returns C<< { id, name } >> of the L3 domain this row's VRF belongs to, or undef
when it cannot be determined. A default-table row is domain 0 without a query.

=cut

sub l3_domain { return row_l3_domain($_[0], $_[0]->get_column('ip')) }

sub TO_JSON {
  my $self = shift;
  my $data = $self->next::method(@_);
  $data->{l3_domain} = $self->l3_domain;
  return $data;
}

1;
