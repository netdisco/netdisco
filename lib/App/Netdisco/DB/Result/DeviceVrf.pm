use utf8;
package App::Netdisco::DB::Result::DeviceVrf;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_vrf");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "vrf",
  { data_type => "text", is_nullable => 0 },
  "kind",
  { data_type => "text", is_nullable => 1 },
  "rd",
  { data_type => "text", is_nullable => 1 },
  "rt_import",
  { data_type => "text[]", is_nullable => 0, default_value => \"'{}'" },
  "rt_export",
  { data_type => "text[]", is_nullable => 0, default_value => \"'{}'" },
  "l3_isid",
  { data_type => "integer", is_nullable => 1 },
  "listed_by",
  { data_type => "text", is_nullable => 1 },
  "complete",
  { data_type => "boolean", is_nullable => 0, default_value => \"false" },
  "last_discover",
  { data_type => "timestamp", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip", "vrf");

=head1 NAME

App::Netdisco::DB::Result::DeviceVrf

=head1 DESCRIPTION

Every VRF instance a device reports, the default table included as an
empty C<vrf>. A NULL C<rd> means unset.

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table which reported this instance.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

1;
