package Netdisco::DB::ResultSet::DevicePort;
use base 'DBIx::Class::ResultSet';

use strict;
use warnings FATAL => 'all';

=head1 search_by_mac( \%cond, \%attrs? )

 my $set = $rs->search_by_mac({mac => '00:11:22:33:44:55'});

Like C<search()>, this returns a ResultSet of matching rows from the
DevicePort table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<mac> with
the value to search for.

=item *

Results are ordered by the creation timestamp.

=item *

The additional column C<creation_stamp> provides a preformatted timestamp of
the C<creation> field.

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
        order_by => {'-desc' => 'me.creation'},
        '+select' => [
          \"to_char(me.creation, 'YYYY-MM-DD HH24:MI')",
        ],
        '+as' => [qw/ creation_stamp /],
      })
      ->search($cond, $attrs);
}

=head1 search_by_ip( \%cond, \%attrs? )

 my $set = $rs->search_by_ip({ip => '192.0.2.1'});

Like C<search()>, this returns a ResultSet of matching rows from the
DevicePort table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<IP> with the IPv4
or IPv6 value to search for in plain string form.

=item *

The additional column C<lastchange_stamp> provides a preformatted timestamp of
the C<lastchange> field in the C<device_port> table.

=item *

A JOIN is performed on the C<device> table in order to retrieve data required
for the C<lastchange_stamp> calculation.

=back

=cut

sub search_by_ip {
    my ($rs, $cond, $attrs) = @_;

    die "ip address required for search_by_ip\n"
      if ref {} ne ref $cond or !exists $cond->{ip};

    $cond->{'me.ip'} = delete $cond->{ip};
    $attrs ||= {};

    return $rs
      ->search_rs({}, {
        '+select' => [
          \"to_char(last_discover - (uptime - lastchange) / 100 * interval '1 second', 'YYYY-MM-DD HH24:MI:SS')",
        ],
        '+as' => [qw/ lastchange_stamp /],
        join => 'device',
      })
      ->search($cond, $attrs);
}

=head1 search_by_name( \%cond, \%attrs? )

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

=head1 search_by_vlan( \%cond, \%attrs? )

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

=head1 search_by_port( \%cond, \%attrs? )

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
