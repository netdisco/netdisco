package App::Netdisco::SSHCollector::Platform::IOSXR;

# vim: set expandtab tabstop=8 softtabstop=4 shiftwidth=4:

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOSXR

=head1 DESCRIPTION

Collect ARP entries from Cisco IOS XR devices.

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

Returns an array of hashrefs in the format { mac => MACADDR, ip => IPADDR }.

=cut

sub arpnip {
    my ($self, $hostlabel, $ssh, @args) = @_;

    debug "$hostlabel $$ arpnip()";

    my ($pty, $pid) = $ssh->open2pty or die "unable to run remote command";
    my $expect = Expect->init($pty);

    my ($pos, $error, $match, $before, $after);
    my $prompt = qr/#/;

    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    $expect->send("terminal length 0\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    my @arpentries;

    $expect->send("show arp vrf all\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    # 0.0.0.0     00:00:00   0000.0000.0000  Dynamic    ARPA  GigabitEthernet0/0/0/0
    for (split(/\n/, $before)){
        my ($ip, $age, $mac, $state, $t, $iface) = split(/\s+/);
        if ($ip =~ m/(\d{1,3}\.){3}\d{1,3}/ && $mac =~ m/[0-9a-f.]+/i) {
            push(@arpentries, { ip => $ip, mac => $mac });
        }
    }

    return @arpentries;
}

1;
