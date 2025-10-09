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
  "name",
  { data_type => "text", is_nullable => 0 },
  "device_acl",
  { data_type => "integer", is_nullable => 0 },
  "port_acl",
  { data_type => "integer", is_nullable => 1 },
);

__PACKAGE__->set_primary_key("role_name");

1;