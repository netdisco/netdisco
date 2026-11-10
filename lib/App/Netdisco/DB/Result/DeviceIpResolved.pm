package App::Netdisco::DB::Result::DeviceIpResolved;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('device_ip_resolved');
__PACKAGE__->result_source_instance->is_virtual(0);

__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 1 },
  "alias",
  { data_type => "inet", is_nullable => 1 },
);

=head1 NAME

App::Netdisco::DB::Result::DeviceIpResolved

=head1 DESCRIPTION

A database view, created by the schema upgrade, that maps each alias address
to the one device (C<ip>) which owns it. With no VRF in use it returns the
C<(ip, alias)> pairs of C<device_ip> exactly.

=cut

1;
