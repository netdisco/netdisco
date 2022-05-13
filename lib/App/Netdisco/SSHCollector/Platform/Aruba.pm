package App::Netdisco::SSHCollector::Platform::Aruba;

=head1 NAME

App::Netdisco::SSHCollector::Platform::Aruba

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

=back

=cut

sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip()";
    my @data = $ssh->capture("show arp");

    chomp @data;
    my @arpentries;

    # 172.16.20.15  00:24:b2:69:86:7d  vlan    interface   state
    foreach my $line (@data) {
        my @fields = split m/\s+/, $line;

        push @arpentries, { mac => $fields[1], ip => $fields[0] };
    }
    return @arpentries;
}

1;
