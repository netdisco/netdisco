package App::Netdisco::DB::ResultSet::DevicePortLog;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=head2 with_times

This is a modifier for any C<search()> which will add the following additional
synthesized column to the result set:

=over 4

=item creation_stamp

=back

=cut

sub with_times {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => {
          creation_stamp => \"to_char(creation, 'YYYY-MM-DD HH24:MI:SS')",
        },
      });
}

1;
