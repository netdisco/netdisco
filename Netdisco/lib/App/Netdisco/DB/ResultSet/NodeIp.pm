package App::Netdisco::DB::ResultSet::NodeIp;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings FATAL => 'all';

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

my $search_attr = {
    order_by => {'-desc' => 'time_last'},
    '+columns' => [
      'oui.company',
      { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
      { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
    ],
    join => 'oui'
};

=head1 with_times

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item time_first_stamp

=item time_last_stamp

=back

=cut

sub with_times {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs({}, $search_attr)
    ->search($cond, $attrs);
}

=head1 search_by_ip( \%cond, \%attrs? )

 my $set = $rs->search_by_ip({ip => '192.0.2.1', active => 1});

Like C<search()>, this returns a ResultSet of matching rows from the
NodeIp table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<ip> with the value
to search for. Value can either be a simple string of IPv4 or IPv6, or a
L<NetAddr::IP::Lite> object in which case all results within the CIDR/Prefix
will be retrieved.

=item *

Results are ordered by time last seen.

=item *

Additional columns C<time_first_stamp> and C<time_last_stamp> provide
preformatted timestamps of the C<time_first> and C<time_last> fields.

=item *

A JOIN is performed on the OUI table and the OUI C<company> column prefetched.

=back

To limit results only to active IPs, set C<< {active => 1} >> in C<cond>.

=cut

sub search_by_ip {
    my ($rs, $cond, $attrs) = @_;

    die "ip address required for search_by_ip\n"
      if ref {} ne ref $cond or !exists $cond->{ip};

    # handle either plain text IP or NetAddr::IP (/32 or CIDR)
    my ($op, $ip) = ('=', delete $cond->{ip});

    if ('NetAddr::IP::Lite' eq ref $ip and $ip->num > 1) {
        $op = '<<=';
        $ip = $ip->cidr;
    }
    $cond->{ip} = { $op => $ip };

    return $rs
      ->search_rs({}, $search_attr)
      ->search($cond, $attrs);
}

=head1 search_by_name( \%cond, \%attrs? )

 my $set = $rs->search_by_name({dns => 'foo.example.com', active => 1});

Like C<search()>, this returns a ResultSet of matching rows from the
NodeIp table.

=over 4

=item *

The NodeIp table must have a C<dns> column for this search to work. Typically
this column is the IP's DNS PTR record, cached at the time of Netdisco Arpnip.

=item *

The C<cond> parameter must be a hashref containing a key C<dns> with the value
to search for. The value may optionally include SQL wildcard characters.

=item *

Results are ordered by time last seen.

=item *

Additional columns C<time_first_stamp> and C<time_last_stamp> provide
preformatted timestamps of the C<time_first> and C<time_last> fields.

=item *

A JOIN is performed on the OUI table and the OUI C<company> column prefetched.

=back

To limit results only to active IPs, set C<< {active => 1} >> in C<cond>.

=cut

sub search_by_dns {
    my ($rs, $cond, $attrs) = @_;

    die "dns field required for search_by_dns\n"
      if ref {} ne ref $cond or !exists $cond->{dns};

    $cond->{dns} = { '-ilike' => delete $cond->{dns} };

    return $rs
      ->search_rs({}, $search_attr)
      ->search($cond, $attrs);
}

=head1 search_by_mac( \%cond, \%attrs? )

 my $set = $rs->search_by_mac({mac => '00:11:22:33:44:55', active => 1});

Like C<search()>, this returns a ResultSet of matching rows from the
NodeIp table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<mac> with the value
to search for.

=item *

Results are ordered by time last seen.

=item *

Additional columns C<time_first_stamp> and C<time_last_stamp> provide
preformatted timestamps of the C<time_first> and C<time_last> fields.

=item *

A JOIN is performed on the OUI table and the OUI C<company> column prefetched.

=back

To limit results only to active IPs, set C<< {active => 1} >> in C<cond>.

=cut

sub search_by_mac {
    my ($rs, $cond, $attrs) = @_;

    die "mac address required for search_by_mac\n"
      if ref {} ne ref $cond or !exists $cond->{mac};

    return $rs
      ->search_rs({}, $search_attr)
      ->search($cond, $attrs);
}

1;
