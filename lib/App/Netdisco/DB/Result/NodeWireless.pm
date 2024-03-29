use utf8;
package App::Netdisco::DB::Result::NodeWireless;


use strict;
use warnings;

use NetAddr::MAC;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("node_wireless");
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "uptime",
  { data_type => "integer", is_nullable => 1 },
  "maxrate",
  { data_type => "integer", is_nullable => 1 },
  "txrate",
  { data_type => "integer", is_nullable => 1 },
  "sigstrength",
  { data_type => "integer", is_nullable => 1 },
  "sigqual",
  { data_type => "integer", is_nullable => 1 },
  "rxpkt",
  { data_type => "bigint", is_nullable => 1 },
  "txpkt",
  { data_type => "bigint", is_nullable => 1 },
  "rxbyte",
  { data_type => "bigint", is_nullable => 1 },
  "txbyte",
  { data_type => "bigint", is_nullable => 1 },
  "time_last",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "ssid",
  { data_type => "text", is_nullable => 0, default_value => '' },
);
__PACKAGE__->set_primary_key("mac", "ssid");



=head1 RELATIONSHIPS

=head2 oui

DEPRECATED: USE MANUFACTURER INSTEAD

Returns the C<oui> table entry matching this Node. You can then join on this
relation and retrieve the Company name from the related table.

The JOIN is of type LEFT, in case the OUI table has not been populated.

=cut

__PACKAGE__->belongs_to( oui => 'App::Netdisco::DB::Result::Oui',
    sub {
        my $args = shift;
        return {
            "$args->{foreign_alias}.oui" =>
              { '=' => \"substring(cast($args->{self_alias}.mac as varchar) for 8)" }
        };
    },
    { join_type => 'LEFT' }
);

=head2 manufacturer

Returns the C<manufacturer> table entry matching this Node. You can then join on this
relation and retrieve the Company name from the related table.

The JOIN is of type LEFT, in case the Manufacturer table has not been populated.

=cut

__PACKAGE__->belongs_to( manufacturer => 'App::Netdisco::DB::Result::Manufacturer',
  sub {
      my $args = shift;
      return {
        "$args->{foreign_alias}.range" => { '@>' =>
          \qq{('x' || lpad( translate( $args->{self_alias}.mac ::text, ':', ''), 16, '0')) ::bit(64) ::bigint} },
      };
  },
  { join_type => 'LEFT' }
);

=head2 node

Returns the C<node> table entry matching this wireless entry.

The JOIN is of type LEFT, in case the C<node> is no longer present in the
database but the relation is being used in C<search()>.

=cut

__PACKAGE__->belongs_to( node => 'App::Netdisco::DB::Result::Node',
                       { 'foreign.mac' => 'self.mac' },
                       { join_type => 'LEFT' } );

=head1 ADDITIONAL COLUMNS

=head2 net_mac

Returns the C<mac> column instantiated into a L<NetAddr::MAC> object.

=cut

sub net_mac { return NetAddr::MAC->new(mac => ((shift)->mac || '')) }

1;
