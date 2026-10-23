package App::Netdisco::DB::ResultSet::Subnet;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=head2 upsert_subnet( $net, $now )

Records C<$net> as seen at C<$now>, a SQL expression for the time, adding
the row if it is new. One statement, so two pollers that see the same new
subnet at once cannot both try to insert it.

=cut

sub upsert_subnet {
  my ($rs, $net, $now) = @_;
  return unless $net;
  return $rs->result_source->storage->dbh_do(sub {
    my (undef, $dbh) = @_;
    $dbh->do("INSERT INTO subnets (net, last_discover) VALUES (?, $now)"
      .' ON CONFLICT (net) DO UPDATE SET last_discover = EXCLUDED.last_discover', undef, $net);
  });
}

1;
