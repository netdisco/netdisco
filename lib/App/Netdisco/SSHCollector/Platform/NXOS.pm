package App::Netdisco::SSHCollector::Platform::NXOS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::NXOS

=head1 DESCRIPTION

Collect ARP entries from Cisco NXOS devices.

=cut

use strict;
use warnings;

use Dancer ':script';
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.

=back

=cut

sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip()";
    my @data = $ssh->capture("show ip arp vrf all");

    chomp @data;
    my @arpentries;

    #IP ARP Table for all contexts
    #Total number of entries: 5
    #Address         Age       MAC Address     Interface
    #192.168.228.1   00:00:43  0000.abcd.1111  mgmt0
    #192.168.228.9   00:05:24  cccc.7777.1b1b  mgmt0

    foreach (@data) {
        my ($ip, $age, $mac, $iface) = split(/\s+/);

        if ($ip && $ip =~ m/(\d{1,3}\.){3}\d{1,3}/
            && $mac =~ m/([0-9a-f]{4}\.){2}[0-9a-f]{4}/i) {
              push(@arpentries, { ip => $ip, mac => $mac });
        }
    }

    return @arpentries;
}

1;
