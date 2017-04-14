package App::Netdisco::DB::ResultSet::DevicePortSsid;
use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

__PACKAGE__->load_components(
    qw/
        +App::Netdisco::DB::ExplicitLocking
        /
);

=head1 ADDITIONAL METHODS

=head2 get_ssids

Returns a sorted list of SSIDs with the following columns only:

=over 4

=item ssid

=item broadcast

=item count

=back

Where C<count> is the number of instances of the SSID in the Netdisco
database.

=cut

sub get_ssids {
    my $rs = shift;

    return $rs->search(
        {},
        {   select => [ 'ssid', 'broadcast', { count => 'ssid' } ],
            as       => [qw/ ssid broadcast count /],
            group_by => [qw/ ssid broadcast /],
            order_by => { -desc => [qw/count/] },
        }
        )

}

1;
