package App::Netdisco::DB::ResultSet::Subnet;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=head2 upsert_subnet( $net, $now, $vrf, $router )

Records C<$net> as seen at C<$now>, adding the row if it is new. One
statement, so two pollers that see the same new subnet at once cannot both
try to insert it.

C<$now> must be one of the timestamp forms accepted by C<upsert>, such as
C<LOCALTIMESTAMP> or C<to_timestamp(1)::timestamp>.

Optional C<$vrf> names the routing context the subnet was seen in, and
defaults to the empty string (the global table).

Optional C<$router> is the device that reported the subnet, kept as
C<router_last>. Without one the column is left as it was.

=cut

sub upsert_subnet {
  my ($rs, $net, $now, $vrf, $router) = @_;
  return unless $net;
  my %row = (net => $net, vrf => $vrf // '', last_discover => \$now);
  $row{router_last} = $router if defined $router;
  return $rs->upsert([\%row]);
}

1;
