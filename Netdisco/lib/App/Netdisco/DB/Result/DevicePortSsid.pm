use utf8;
package App::Netdisco::DB::Result::DevicePortSsid;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("device_port_ssid");
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 1 },
  "ssid",
  { data_type => "text", is_nullable => 1 },
  "broadcast",
  { data_type => "boolean", is_nullable => 1 },
  "bssid",
  { data_type => "macaddr", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:zvgylKzUQtizJZCe1rEdUg

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table which hosts this SSID.

=cut

__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 port

Returns the entry from the C<port> table which corresponds to this SSID.

=cut

__PACKAGE__->belongs_to( port => 'App::Netdisco::DB::Result::DevicePort', {
    'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
