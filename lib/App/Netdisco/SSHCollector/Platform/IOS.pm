package App::Netdisco::SSHCollector::Platform::IOS;

# vim: set expandtab tabstop=8 softtabstop=4 shiftwidth=4:

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOS

=head1 DESCRIPTION

Collect ARP entries from Cisco IOS devices.

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

    debug "$hostlabel $$ arpnip()";
    my @data = $ssh->capture("show ip arp");

    chomp @data;
    my @arpentries;

    # Internet  172.16.20.15   13   0024.b269.867d  ARPA FastEthernet0/0.1
    foreach my $line (@data) {
        next unless $line =~ m/^Internet/;
        my @fields = split m/\s+/, $line;

        push @arpentries, { mac => $fields[3], ip => $fields[1] };
    }

    return @arpentries;
}

1;
