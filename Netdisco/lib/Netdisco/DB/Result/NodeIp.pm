use utf8;
package Netdisco::DB::Result::NodeIp;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';
__PACKAGE__->table("node_ip");
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "ip",
  { data_type => "inet", is_nullable => 0 },
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
__PACKAGE__->set_primary_key("mac", "ip");


# Created by DBIx::Class::Schema::Loader v0.07015 @ 2012-01-07 14:20:02
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:9+CuvuVWH88WxAf6IBij8g

=head1 GENERAL NOTES

This Result Class for the C<node_ip> table supports sites that have customized
their table to include a C<dns> column, containing a cached DNS record for the
Node at the time of discovery.

Calling the C<dns()> accessor will either return the content of that field if
the field is configured and installed, or else perform a live DNS lookup on
the IP field within the record (returning the first PTR, or undef).

To enable this feature, set the C<HAVE_NODEIP_DNS_COL> environment variable to
a true value. In the Netdisco web app you can activate the column using the
C<have_nodeip_dns_col> application setting, instead.

=cut

__PACKAGE__->add_column("dns" =>
  { data_type => "text", is_nullable => 1, accessor => undef });

# some customize their node_ip table to have a dns column which
# is the cached record at the time of discovery
sub dns {
  my $row = shift;
  return $row->get_column('dns')
    if $row->result_source->has_column('dns');

  use Net::DNS ();
  my $q = Net::DNS::Resolver->new->query($row->ip);
  if ($q) {
    foreach my $rr ($q->answer) {
      next unless $rr->type eq 'PTR';
      return $rr->ptrdname;
    }
  }
  return undef;
}

=head1 RELATIONSHIPS

=head2 oui

Returns the C<oui> table entry matching this Node. You can then join on this
relation and retrieve the Company name from the related table.

The JOIN is of type LEFT, in case the OUI table has not been populated.

=cut

__PACKAGE__->belongs_to( oui => 'Netdisco::DB::Result::Oui',
    sub {
        my $args = shift;
        return {
            "$args->{foreign_alias}.oui" =>
              { '=' => \"substring(cast($args->{self_alias}.mac as varchar) for 8)" }
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

__PACKAGE__->has_many( node_ips => 'Netdisco::DB::Result::NodeIp',
  { 'foreign.mac' => 'self.mac' } );

=head2 nodes

Returns the set of C<node> entries associated with this IP. That is, all the
MAC addresses recorded which have ever hosted this IP Address.

Remember you can pass a filter to this method to find only active or inactive
nodes, but do take into account that both the C<node> and C<node_ip> tables
include independent C<active> fields.

See also the C<node_sightings> helper routine, below.

=cut

__PACKAGE__->has_many( nodes => 'Netdisco::DB::Result::Node',
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
    $rs = $rs->search_rs({}, {'+columns' => 'dns'})
      if $rs->has_dns_col;

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

1;
