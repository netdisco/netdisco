package App::Netdisco::DB::ResultSet::Admin;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=head2 skipped( $backend?, $max_deferrals?, $retry_after? )

Returns a correlated subquery for the set of C<device_skip> entries that apply
to some jobs. They match the device IP, current backend, and job action.

Pass the C<backend> FQDN (or the current host will be used as a default), the
C<max_deferrals> (option disabled if 0/undef value is passed), and
C<retry_after> when devices will be retried once (disabled if 0/undef passed).

=cut

sub skipped {
  my ($rs, $backend, $max_deferrals, $retry) = @_;
  $backend ||= 'fqdn-undefined';
  $max_deferrals ||= (2**30); # not really 'disabled'
  $retry ||= '100 years'; # not really 'disabled'

  return $rs->correlate('device_skips')->search(undef,{
    # NOTE: bind param list order is significant
    bind => [[deferrals => $max_deferrals], [last_defer => $retry], [backend => $backend]],
  });
}

=head2 with_times

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item entered_stamp

=item started_stamp

=item finished_stamp

=back

=cut

sub with_times {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => {
          entered_stamp => \"to_char(entered, 'YYYY-MM-DD HH24:MI')",
          started_stamp => \"to_char(started, 'YYYY-MM-DD HH24:MI')",
          finished_stamp => \"to_char(finished, 'YYYY-MM-DD HH24:MI')",
        },
      });
}

1;
