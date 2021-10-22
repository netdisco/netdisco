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
use Expect;
use Regexp::Common 'net';

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

    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        warn "unable to run remote command [$hostlabel] " . $ssh->error;
        return ();
    }

    #$Expect::Debug = 1;
    #$Expect::Exp_Internal = 1;

    my $expect = Expect->init($pty);
    $expect->raw_pty(1);

    my ($pos, $error, $match, $before, $after);
    my $prompt = qr/# +$/;
    my $timeout = 10;

    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    $expect->send("terminal length 0\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    # we filter on the : in Age as the output header of the command may contain prompt chars, e.g.
    # Flags:   # - Adjacencies Throttled for Glean
    $expect->send("show ip arp vrf all | inc :\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my @arpentries;
    my @data = split(/\R/, $before);

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

    $expect->send("show ipv6 neighbor vrf all | exclude Flags:\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my @data6 = split(/\R/, $before);

    #IPv6 neighbors use this two-line format
    #IPv6 Adjacency Table for all VRFs
    #Total number of entries: 65
    #Address         Age       MAC Address     Pref Source     Interface
    #bff:a90:c405:120::3
    #                00:01:46  5c71.0d42.df3f  50   icmpv6     Vlan376
    #bff:a90:c405:120::52
    #                    3w0d  9440.c988.b6fd  50   icmpv6     Vlan376


    my $prevline;
    foreach my $line (@data6) {

        my (undef, $age, $mac, $pref, $src, $iface) = split(/\s+/, $line);
        if ($mac && $mac =~ m/([0-9a-f]{4}\.){2}[0-9a-f]{4}/i && $prevline =~ /$RE{net}{IPv6}/) {
            push(@arpentries, { ip => $prevline, mac => $mac });
        }

        $prevline = $line;
    }

    return @arpentries;
}

1;


