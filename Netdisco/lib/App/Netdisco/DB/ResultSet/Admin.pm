package App::Netdisco::DB::ResultSet::Admin;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings FATAL => 'all';

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

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
