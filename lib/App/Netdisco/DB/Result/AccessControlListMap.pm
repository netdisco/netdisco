package App::Netdisco::DB::Result::AccessControlListMap;
use utf8;
use strict;
use warnings;

use base 'App::Netdisco::DB::Result';

=head1 NAME

App::Netdisco::DB::Result::AccessControlListMap

=head1 DESCRIPTION

Single ACL mapping within a named ACL.

Left ACL must always be there. Right is optional.

=cut

__PACKAGE__->table('access_control_list_map');

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_nullable => 0, is_auto_increment => 1 },
  "acl_name",
  { data_type => "text", is_nullable => 0 },
  "left_acl_id",
  { data_type => "integer", is_nullable => 0 },
  "right_acl_id",
  { data_type => "integer", is_nullable => 1 },
);

__PACKAGE__->set_primary_key("id");

__PACKAGE__->belongs_to( left_acl => 'App::Netdisco::DB::Result::AccessControlList',
  { 'foreign.id' => 'self.left_acl_id' }, { cascade_delete => 1 } );

__PACKAGE__->belongs_to( left_acl_with_dns => 'App::Netdisco::DB::Result::Virtual::ACLEntriesWithDNS',
  { 'foreign.id' => 'self.left_acl_id' }, { cascade_delete => 1 } );

__PACKAGE__->belongs_to( right_acl => 'App::Netdisco::DB::Result::AccessControlList',
  { 'foreign.id' => 'self.right_acl_id' }, { cascade_delete => 1, join_type => 'left' } );

__PACKAGE__->belongs_to( right_acl_with_dns => 'App::Netdisco::DB::Result::Virtual::ACLEntriesWithDNS',
  { 'foreign.id' => 'self.right_acl_id' }, { cascade_delete => 1, join_type => 'left' } );

1;