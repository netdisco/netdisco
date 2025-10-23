use utf8;
package App::Netdisco::DB::Result::NodeIp;


use strict;
use warnings;

use NetAddr::MAC;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("node_ip");
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "dns",
  { data_type => "text", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "time_first",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "time_last",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "seen_on_router_first",
  { data_type => "jsonb", is_nullable => 0, default_value => \"{}" },
  "seen_on_router_last",
  { data_type => "jsonb", is_nullable => 0, default_value => \"{}" },
  "vrf",
  { data_type => "text", is_nullable => 0, default => '' },
);
__PACKAGE__->set_primary_key("mac", "ip", "vrf");



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

=head2 router

Returns the C<device> table entry matching this Node's router. You can then join on
this relation and retrieve the Device DNS name.

The JOIN is of type LEFT, in case there's no recorded router on this record.

=cut

__PACKAGE__->belongs_to( router => 'App::Netdisco::DB::Result::Device',
  sub {
      my $args = shift;
      return {
        "host($args->{foreign_alias}.ip)" => { '=' =>
          \q{(SELECT key FROM json_each_text(seen_on_router_last::json) ORDER BY value::timestamp DESC LIMIT 1)} },
      };
  },
  { join_type => 'LEFT' }
);

=head2 node_ips

Returns the set of all C<node_ip> entries which are associated together with
this IP. That is, all the IP addresses hosted on the same interface (MAC
address) as the current Node IP entry.

Note that the set will include the original Node IP object itself. If you wish
to find the I<other> IPs excluding this one, see the C<ip_aliases> helper
routine, below.

Remember you can pass a filter to this method to find only active or inactive
nodes, but do take into account that both the C<node> and C<node_ip> tables
include independent C<active> fields.

=cut

__PACKAGE__->has_many( node_ips => 'App::Netdisco::DB::Result::NodeIp',
  { 'foreign.mac' => 'self.mac' } );

=head2 nodes

Returns the set of C<node> entries associated with this IP. That is, all the
MAC addresses recorded which have ever hosted this IP Address.

Remember you can pass a filter to this method to find only active or inactive
nodes, but do take into account that both the C<node> and C<node_ip> tables
include independent C<active> fields.

See also the C<node_sightings> helper routine, below.

=cut

__PACKAGE__->has_many( nodes => 'App::Netdisco::DB::Result::Node',
  { 'foreign.mac' => 'self.mac' }, { order_by => { '-desc' => 'time_last' }} );

=head2 netbios

Returns the set of C<node_nbt> entries associated with the MAC of this IP.
That is, all the NetBIOS entries recorded which shared the same MAC with this
IP Address.

=cut

__PACKAGE__->has_many( netbios => 'App::Netdisco::DB::Result::NodeNbt',
  { 'foreign.mac' => 'self.mac' } );

my $search_attr = {
    order_by => {'-desc' => 'time_last'},
    '+columns' => {
      time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')",
      time_last_stamp => \"to_char(time_last, 'YYYY-MM-DD HH24:MI')",
    },
};

=head2 ip_aliases( \%cond, \%attrs? )

Returns the set of other C<node_ip> entries hosted on the same interface (MAC
address) as the current Node IP, excluding the current IP itself.

Remember you can pass a filter to this method to find only active or inactive
nodes, but do take into account that both the C<node> and C<node_ip> tables
include independent C<active> fields.

=over 4

=item *

Results are ordered by time last seen.

=item *

Additional columns C<time_first_stamp> and C<time_last_stamp> provide
preformatted timestamps of the C<time_first> and C<time_last> fields.

=back

=cut

sub ip_aliases {
    my ($row, $cond, $attrs) = @_;

    my $rs = $row->node_ips({ip  => { '!=' => $row->ip }});

    return $rs
      ->search_rs({}, $search_attr)
      ->search($cond, $attrs);
}

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
        '+columns' => [qw/ device.dns device.name /],
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

=head2 router_ip

Returns the router IP that most recently reported this MAC-IP pair.

=cut

sub router_ip { return (shift)->get_column('router_ip') }

=head2 router_name

Returns the router DNS or SysName that most recently reported this MAC-IP pair.

May be blank if there's no SysName or DNS name, so you have C<router_ip> as well.

=cut

sub router_name { return (shift)->get_column('router_name') }

=head2 net_mac

Returns the C<mac> column instantiated into a L<NetAddr::MAC> object.

=cut

sub net_mac { return NetAddr::MAC->new(mac => ((shift)->mac || '')) }

1;
