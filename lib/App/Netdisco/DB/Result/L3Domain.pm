use utf8;
package App::Netdisco::DB::Result::L3Domain;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("l3_domain");
__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "text", is_nullable => 0 },
  "inferred_name",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 NAME

App::Netdisco::DB::Result::L3Domain

=head1 DESCRIPTION

A set of VRF instances whose address space is shared. Domain 0, named by
the empty string, is the default table.

=head1 RELATIONSHIPS

=head2 members

Returns the C<l3_domain_member> rows placed in this domain.

=cut

__PACKAGE__->has_many( members => 'App::Netdisco::DB::Result::L3DomainMember',
  { 'foreign.domain_id' => 'self.id' } );

1;
