package App::Netdisco::DB::Result::AccessControlListName;
use utf8;
use strict;
use warnings;

use base 'App::Netdisco::DB::Result';

=head1 NAME

App::Netdisco::DB::Result::AccessControlListName

=head1 DESCRIPTION

Names an ACL.

=cut

__PACKAGE__->table('access_control_list_name');

__PACKAGE__->add_columns(
  "acl_name",
  { data_type => "text", is_nullable => 0 },
  "acl_type",
  { data_type => "text", is_nullable => 0 },
  # type TEXT NOT NULL CHECK (type IN ('host', 'host_host', 'host_port')),
);

__PACKAGE__->set_primary_key("acl_name");

__PACKAGE__->has_many( mappings => 'App::Netdisco::DB::Result::AccessControlListMap',
  { 'foreign.acl_name' => 'self.acl_name' } );

1;