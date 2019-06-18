package App::Netdisco::SSHCollector::Platform::BigIP;

# vim: set expandtab tabstop=8 softtabstop=4 shiftwidth=4:

=head1 NAME

App::Netdisco::SSHCollector::Platform::BigIP

=head1 DESCRIPTION

Collect ARP entries from F5 BigIP load balancers. These are Linux boxes,
but feature an additional, proprietary IP stack which does not show
up in the standard SNMP ipNetToMediaTable.

These devices also feature a CLI interface similar to IOS, which can
either be set as the login shell of the user, or be called from an
ordinary shell. This module assumes the former, and if "show net arp"
can't be executed, falls back to the latter.

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

    my @data = $ssh->capture("show net arp");
    unless (@data){
        @data = $ssh->capture('tmsh -c "show net arp"');
    }

    chomp @data;
    my @arpentries;

    foreach (@data){
        if (m/\d{1,3}\..*resolved/){
            my (undef, $ip, $mac) = split(/\s+/);

            # ips can look like 172.19.254.143%10, clean
            $ip =~ s/%\d+//;

            push(@arpentries, {mac => $mac, ip => $ip});
        }
    }

    return @arpentries;
}

1;
