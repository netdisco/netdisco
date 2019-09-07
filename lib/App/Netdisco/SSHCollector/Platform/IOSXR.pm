package App::Netdisco::SSHCollector::Platform::IOSXR;

# vim: set expandtab tabstop=8 softtabstop=4 shiftwidth=4:

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOSXR

=head1 DESCRIPTION

Collect ARP entries from Cisco IOSXR devices.

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

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

=back

=cut

sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    # IOSXR show commands seem to depend on an available STDIN
    unless (-t STDIN){
        open STDIN, "<", "/dev/zero" or warn "Failed to fake stdin: $!";
    }

    debug "$hostlabel $$ arpnip()";
    my @data = $ssh->capture("show arp vrf all");

    chomp @data;
    my @arpentries;

    # 0.0.0.0     00:00:00   0000.0000.0000  Dynamic    ARPA  GigabitEthernet0/0/0/0
    foreach (@data) {

        my ($ip, $age, $mac, $state, $t, $iface) = split(/\s+/);

        if ($ip =~ m/(\d{1,3}\.){3}\d{1,3}/
            && $mac =~ m/([0-9a-f]{4}\.){2}[0-9a-f]{4}/i) {
              push(@arpentries, { ip => $ip, mac => $mac });
        }
    }

    return @arpentries;
}

1;
