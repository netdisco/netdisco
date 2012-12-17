package App::Netdisco::DB::ResultSet::Node;
use base 'DBIx::Class::ResultSet';

use strict;
use warnings FATAL => 'all';

=head1 search_by_mac( \%cond, \%attrs? )

 my $set = $rs->search_by_mac({mac => '00:11:22:33:44:55', active => 1});

Like C<search()>, this returns a ResultSet of matching rows from the Node
table.

=over 4

=item *

The C<cond> parameter must be a hashref containing a key C<mac> with
the value to search for.

=item *

Results are ordered by time last seen.

=item *

Additional columns C<time_first_stamp> and C<time_last_stamp> provide
preformatted timestamps of the C<time_first> and C<time_last> fields.

=item *

A JOIN is performed on the Device table and the Device C<dns> column
prefetched.

=back

To limit results only to active nodes, set C<< {active => 1} >> in C<cond>.

=cut

sub search_by_mac {
    my ($rs, $cond, $attrs) = @_;

    die "mac address required for search_by_mac\n"
      if ref {} ne ref $cond or !exists $cond->{mac};

    $cond->{'me.mac'} = delete $cond->{mac};

    return $rs
      ->search_rs({}, {
        order_by => {'-desc' => 'time_last'},
        '+columns' => [
          'device.dns',
          { time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')" },
          { time_last_stamp =>  \"to_char(time_last, 'YYYY-MM-DD HH24:MI')" },
        ],
        join => 'device',
      })
      ->search($cond, $attrs);
}

1;
