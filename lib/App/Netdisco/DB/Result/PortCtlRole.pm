package App::Netdisco::DB::Result::PortCtlRole;
use utf8;
use strict;
use warnings;

use base 'App::Netdisco::DB::Result';

=head1 NAME

App::Netdisco::DB::Result::PortCtlRole

=head1 DESCRIPTION

PortControl permissions for device ports by role.

=cut

__PACKAGE__->table('portctl_role');

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_nullable => 0, is_auto_increment => 1 },
  "role_name",
  { data_type => "text", is_nullable => 0 },
  "device_acl_id",
  { data_type => "integer", is_nullable => 0 },
  "port_acl_id",
  { data_type => "integer", is_nullable => 0 },
);

__PACKAGE__->set_primary_key("id");

__PACKAGE__->belongs_to( device_acl => 'App::Netdisco::DB::Result::AccessControlList',
  { 'foreign.id' => 'self.device_acl_id' }, { cascade_delete => 1 } );

__PACKAGE__->belongs_to( port_acl => 'App::Netdisco::DB::Result::AccessControlList',
  { 'foreign.id' => 'self.port_acl_id' }, { cascade_delete => 1 } );

1;