use utf8;
package App::Netdisco::DB::Result::L3DomainMember;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("l3_domain_member");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "vrf",
  { data_type => "text", is_nullable => 0 },
  "domain_id",
  { data_type => "integer", is_nullable => 0 },
  "reason",
  { data_type => "text", is_nullable => 0 },
  "source",
  { data_type => "text", is_nullable => 0 },
);
__PACKAGE__->set_primary_key("ip", "vrf");

=head1 NAME

App::Netdisco::DB::Result::L3DomainMember

=head1 DESCRIPTION

Places one VRF instance of one device in an L3 domain. C<source> is
C<inferred> or C<manual>.

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table holding this instance.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 domain

Returns the L3 domain this instance belongs to.

=cut

__PACKAGE__->belongs_to( domain => 'App::Netdisco::DB::Result::L3Domain',
  { 'foreign.id' => 'self.domain_id' } );

1;
