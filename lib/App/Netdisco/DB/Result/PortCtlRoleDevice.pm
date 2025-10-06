package App::Netdisco::DB::Result::PortCtlRoleDevice;
use utf8;
use strict;
use warnings;

use base 'App::Netdisco::DB::Result';

=head1 NAME

App::Netdisco::DB::Result::PortControl

=head1 DESCRIPTION

PortControl permissions for device ports by role.

=cut

__PACKAGE__->table('portctl_role_device');

__PACKAGE__->add_columns(
  "role_name",
  { data_type => "text", is_nullable => 0 },
  "device_ip",
  { data_type => "inet", is_nullable => 0 },
);

__PACKAGE__->set_primary_key("role_name", "device_ip");


1;