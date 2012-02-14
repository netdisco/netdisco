package Netdisco::DB::ResultSet::DevicePort;
use base 'DBIx::Class::ResultSet';

use strict;
use warnings FATAL => 'all';

=head1 ADDITIONAL METHODS

=head2 with_times

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item lastchange_stamp

=back

=cut

sub with_times {
  my ($rs, $cond, $attrs) = @_;
  $cond  ||= {};
  $attrs ||= {};

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+select' => [
          \"to_char(device.last_discover - (device.uptime - lastchange) / 100 * interval '1 second',
                      'YYYY-MM-DD HH24:MI:SS')",
        ],
        '+as' => [qw/ lastchange_stamp /],
        join => 'device',
      });
}

=head2 with_node_age

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item $nodes.time_last_age

=back

You can pass in the table alias for the Nodes relation, which defaults to
C<nodes>.

=cut

sub with_node_age {
  my ($rs, $alias) = @_;
  $alias ||= 'nodes';

  return $rs
    ->search_rs({},
      {
        '+select' =>
          [\"replace(age(date_trunc('minute', $alias.time_last + interval '30 second'))::text, 'mon', 'month')"],
        '+as' => [ "$alias.time_last_age" ],
      });
}

=head2 with_vlan_count

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item tagged_vlans_count

=back

=cut

sub with_vlan_count {
  my ($rs, $cond, $attrs) = @_;
  $cond  ||= {};
  $attrs ||= {};

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+select' => [ { count => 'port_vlans_tagged.vlan' } ],
        '+as' => [qw/ tagged_vlans_count /],
        join => 'port_vlans_tagged',
        distinct => 1,
      });
}

=head2 search_by_mac( \%cond, \%attrs? )

 my $set = $rs->search_by_mac({mac => '00:11:22:33:44:55'});

Like C<search()>, this returns a ResultSet of matching rows from the
DevicePort table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<mac> with
the value to search for.

=item *

Results are ordered by the port's Device IP and Port fields.

=back

=cut

sub search_by_mac {
    my ($rs, $cond, $attrs) = @_;

    die "mac address required for search_by_mac\n"
      if ref {} ne ref $cond or !exists $cond->{mac};

    $cond->{'me.mac'} = delete $cond->{mac};
    $attrs ||= {};

    return $rs
      ->search_rs({}, {
        # order_by => {'-desc' => 'me.creation'},
        order_by => [qw/ me.ip me.port /],
      })
      ->search($cond, $attrs);
}

=head2 search_by_ip( \%cond, \%attrs? )

 my $set = $rs->search_by_ip({ip => '192.0.2.1'});

Like C<search()>, this returns a ResultSet of matching rows from the
DevicePort table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<IP> with the IPv4
or IPv6 value to search for in plain string form.

=back

=cut

sub search_by_ip {
    my ($rs, $cond, $attrs) = @_;

    die "ip address required for search_by_ip\n"
      if ref {} ne ref $cond or !exists $cond->{ip};

    $cond->{'me.ip'} = delete $cond->{ip};
    $attrs ||= {};

    return $rs->search($cond, $attrs);
}

=head2 search_by_name( \%cond, \%attrs? )

 my $set = $rs->search_by_name({name => 'sniffer'});

Like C<search()>, this returns a ResultSet of matching rows from the
DevicePort table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<name> with the
value to search for. The value may optionally include SQL wildcard characters.

=item *

Results are ordered by the port's Device IP and Port fields.

=back

=cut

sub search_by_name {
    my ($rs, $cond, $attrs) = @_;

    die "name required for search_by_name\n"
      if ref {} ne ref $cond or !exists $cond->{name};

    $cond->{'me.name'} = { '-ilike' => delete $cond->{name} };
    $attrs ||= {};

    return $rs
      ->search_rs({}, {
        order_by => [qw/ me.ip me.port /],
      })
      ->search($cond, $attrs);
}

=head2 search_by_vlan( \%cond, \%attrs? )

 my $set = $rs->search_by_vlan({vlan => 123});

Like C<search()>, this returns a ResultSet of matching rows from the
DevicePort table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<vlan> with the
value to search for.

=item *

Results are ordered by the port's Device IP and Port fields.

=back

=cut

sub search_by_vlan {
    my ($rs, $cond, $attrs) = @_;

    die "vlan number required for search_by_vlan\n"
      if ref {} ne ref $cond or !exists $cond->{vlan};

    $cond->{'me.vlan'} = delete $cond->{vlan};
    $attrs ||= {};

    return $rs
      ->search_rs({}, {
        order_by => [qw/ me.ip me.port /],
      })
      ->search($cond, $attrs);
}

=head2 search_by_port( \%cond, \%attrs? )

 my $set = $rs->search_by_port({port => 'FastEthernet0/23'});

Like C<search()>, this returns a ResultSet of matching rows from the
DevicePort table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<port> with the
value to search for.

=item *

Results are ordered by the port's Device IP.

=back

=cut

sub search_by_port {
    my ($rs, $cond, $attrs) = @_;

    die "port required for search_by_port\n"
      if ref {} ne ref $cond or !exists $cond->{port};

    $cond->{'me.port'} = delete $cond->{port};
    $attrs ||= {};

    return $rs
      ->search_rs({}, {
        order_by => [qw/ me.ip /],
      })
      ->search($cond, $attrs);
}

1;
