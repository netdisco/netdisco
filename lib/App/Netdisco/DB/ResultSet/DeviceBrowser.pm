package App::Netdisco::DB::ResultSet::DeviceBrowser;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

=head1 ADDITIONAL METHODS

=head2 with_snmp_object( $ip )

Returns a correlated subquery for the set of C<snmp_object> entry for 
the walked data row.

=cut

sub with_snmp_object {
  my ($rs, $ip) = @_;
  $ip ||= '255.255.255.255';

  return $rs->search(undef,{
    # NOTE: bind param list order is significant
    join => ['snmp_object'],
    bind => [$ip],
    prefetch => 'snmp_object',
  });
}

1;
