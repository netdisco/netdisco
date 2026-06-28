package App::Netdisco::DB::Result::AccessControlList;
use utf8;
use strict;
use warnings;

use base 'App::Netdisco::DB::Result';

=head1 NAME

App::Netdisco::DB::Result::AccessControlList

=head1 DESCRIPTION

Models an ACL in the database.

=cut

__PACKAGE__->table('access_control_list_name');

__PACKAGE__->add_columns(
  "name",
  { data_type => "text", is_nullable => 0 },
  "type",
  { data_type => "text", is_nullable => 0 },
  # type TEXT NOT NULL CHECK (type IN ('host', 'host_host', 'host_port')),
);

__PACKAGE__->set_primary_key("name");

__PACKAGE__->has_many( mappings => 'App::Netdisco::DB::Result::AccessControlListMap',
  { 'foreign.acl_name' => 'self.name' } );

1;