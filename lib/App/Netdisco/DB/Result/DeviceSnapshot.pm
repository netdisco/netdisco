use utf8;
package App::Netdisco::DB::Result::DeviceSnapshot;

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_snapshot");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "cache",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("ip");

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table on which this snapshot was created.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

1;
