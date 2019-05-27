use utf8;
package App::Netdisco::DB::Result::NodeNbt;


use strict;
use warnings;

use NetAddr::MAC;

use base 'DBIx::Class::Core';
__PACKAGE__->table("node_nbt");
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "ip",
  { data_type => "inet", is_nullable => 1 },
  "nbname",
  { data_type => "text", is_nullable => 1 },
  "domain",
  { data_type => "text", is_nullable => 1 },
  "server",
  { data_type => "boolean", is_nullable => 1 },
  "nbuser",
  { data_type => "text", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "time_first",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
  "time_last",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 1,
    original      => { default_value => \"now()" },
  },
);
__PACKAGE__->set_primary_key("mac");



=head1 RELATIONSHIPS

=head2 oui

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

=head2 nodes

Returns the set of C<node> entries associated with this IP. That is, all the
MAC addresses recorded which have ever hosted this IP Address.

Remember you can pass a filter to this method to find only active or inactive
nodes, but do take into account that both the C<node> and C<node_nbt> tables
include independent C<active> fields.

See also the C<node_sightings> helper routine, below.

=cut

__PACKAGE__->has_many( nodes => 'App::Netdisco::DB::Result::Node',
  { 'foreign.mac' => 'self.mac' } );


=head2 nodeips

Returns the set of C<node_ip> entries associated with this NetBIOS entry.
That is, the IP addresses which the same MAC address at the time of discovery.

Note that the Active status of the returned IP entries will all be the same
as the current NetBIOS entry.

=cut

__PACKAGE__->has_many( nodeips => 'App::Netdisco::DB::Result::NodeIp',
  { 'foreign.mac' => 'self.mac', 'foreign.active' => 'self.active' } );


my $search_attr = {
    order_by => {'-desc' => 'time_last'},
    '+columns' => {
      time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')",
      time_last_stamp => \"to_char(time_last, 'YYYY-MM-DD HH24:MI')",
    },
};

=head2 node_sightings( \%cond, \%attrs? )

Returns the set of C<node> entries associated with this IP. That is, all the
MAC addresses recorded which have ever hosted this IP Address.

Remember you can pass a filter to this method to find only active or inactive
nodes, but do take into account that both the C<node> and C<node_ip> tables
include independent C<active> fields.

=over 4

=item *

Results are ordered by time last seen.

=item *

Additional columns C<time_first_stamp> and C<time_last_stamp> provide
preformatted timestamps of the C<time_first> and C<time_last> fields.

=item *

A JOIN is performed on the Device table and the Device DNS column prefetched.

=back

=cut

sub node_sightings {
    my ($row, $cond, $attrs) = @_;

    return $row
      ->nodes({}, {
        '+columns' => [qw/ device.dns /],
        join => 'device',
      })
      ->search_rs({}, $search_attr)
      ->search($cond, $attrs);
}

=head1 ADDITIONAL COLUMNS

=head2 time_first_stamp

Formatted version of the C<time_first> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub time_first_stamp { return (shift)->get_column('time_first_stamp') }

=head2 time_last_stamp

Formatted version of the C<time_last> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

sub time_last_stamp  { return (shift)->get_column('time_last_stamp')  }

=head2 net_mac

Returns the C<mac> column instantiated into a L<NetAddr::MAC> object.

=cut

sub net_mac { return NetAddr::MAC->new(mac => (shift)->mac) }

1;
