package App::Netdisco::DB::ResultSet::Subnet;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=head2 upsert_subnet( $net, $now )

Records C<$net> as seen at C<$now>, adding the row if it is new. One
statement, so two pollers that see the same new subnet at once cannot both
try to insert it.

C<$now> must be one of the timestamp forms accepted by C<upsert>, such as
C<LOCALTIMESTAMP> or C<to_timestamp(1)::timestamp>.

=cut

sub upsert_subnet {
  my ($rs, $net, $now) = @_;
  return unless $net;
  return $rs->upsert([{ net => $net, vrf => '', last_discover => \$now }]);
}

1;
