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
use NetAddr::MAC qw/mac_as_ieee/;
use Regexp::Common 'net';

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.

=back

=cut

my $if_name_map = {
  Vl => "Vlan",
  Lo => "Loopback",
  Eth => "Ethernet",
  Po => "Port-channel",
};

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

    # we filter on the : in Age as the output header of the command may contain prompt chars, e.g.
    # Flags:   # - Adjacencies Throttled for Glean
    $expect->send("show ip arp vrf all | inc ^[1-9] | no-more\n");
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

    $expect->send("show ipv6 neighbor vrf all | exclude Flags: | no-more\n");
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
    # Occasionally it uses a one-line format
    #2620:0:e50:1::b    1d01h  84b5.9ca0.bf39  50   icmpv6     Ethernet14/7
    #2620:0:e50:1::f    1d01h  cce1.7f96.1139  50   icmpv6     Ethernet14/7

    my $prevline;
    foreach my $line (@data6) {
        my ($addr, $age, $mac, $pref, $src, $iface) = split(/\s+/, $line);
        # Check to see if everything is on one line
        if ($addr and $addr =~ /$RE{net}{IPv6}/
                  and ($mac and $mac =~ m/([0-9a-f]{4}\.){2}[0-9a-f]{4}/i)) {
            push(@arpentries, { ip => $addr, mac => $mac });
        }
        # It's on two lines
        elsif ($mac and $mac =~ m/([0-9a-f]{4}\.){2}[0-9a-f]{4}/i
                    and $prevline =~ /$RE{net}{IPv6}/) {
            push(@arpentries, { ip => $prevline, mac => $mac });
        }
        
        $prevline = $line;
    }

    return @arpentries;
}

sub macsuck {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ macsuck()";
    my $cmds = <<EOF;
show mac address-table | no-more
EOF
    my @data = $ssh->capture({stdin_data => $cmds}); chomp @data;
    if ($ssh->error) {
        info "$hostlabel $$ error in SSH command " . $ssh->error;
        return
    }

    #hostname# show mac address-table
    #Legend:
    #        * - primary entry, G - Gateway MAC, (R) - Routed MAC, O - Overlay MAC
    #        age - seconds since last seen,+ - primary entry using vPC Peer-Link,
    #        (T) - True, (F) - False, C - ControlPlane MAC, ~ - vsan,
    #        (NA)- Not Applicable
    #   VLAN     MAC Address      Type      age     Secure NTFY Ports
    #---------+-----------------+--------+---------+------+----+------------------
    #+  234     d239.ea50.166a   dynamic  NA         F      F    Po1122
    #C    3     0050.5650.66d8   dynamic  NA         F      F    nve1(192.168.64.2)
    #G    -     0200.c0a8.4003   static   -         F      F    sup-eth1(R)
    #G 1024     648f.3e48.aa4b   static   -         F      F    vPC Peer-Link(R)
    #* 1509     246e.9618.bc72   dynamic  NA         F      F    Eth1/12
    
    my $re_mac_line = qr/^[CG\*\+]\s+([-0-9]+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+\S+\s+([0-9]+|-|NA)\s+[FT]\s+[FT]\s+(([a-zA-Z]+)([0-9\/\.]*).*)$/i;
    my $macentries = {};

    foreach my $line (@data) {
        if ($line && $line =~ m/$re_mac_line/) {
            my $port = sprintf '%s%s', ($if_name_map->{$5} || $4), ($6 || '');
            my $vlan = ($1 ? ($1 eq '-' ? 0 : $1) : 0);

            ++$macentries->{$vlan}->{$port}->{mac_as_ieee($2)};
        }
    }

    return $macentries;
}

sub subnets {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ subnets()";

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

    #    IP Route Table for VRF "xyz"
    #'*' denotes best ucast next-hop
    #'**' denotes best mcast next-hop
    #'[x/y]' denotes [preference/metric]
    #'%<string>' in via output denotes VRF <string>
    #
    #0.0.0.0/0, ubest/mbest: 1/0 time
    #    *via 10.255.254.17, [1/0], 7w1d, static
    #10.1.1.0/24, ubest/mbest: 1/0 time, attached
    #    *via 10.1.1.2, Vlan1234, [0/0], 1y13w, direct
    #10.1.1.1/32, ubest/mbest: 1/0 time, attached
    #    *via 10.1.1.1, Vlan1234, [0/0], 1y13w, hsrp

    # include only lines with "attached" and exclude /32 subnets
    $expect->send("show ip route vrf all | inc attached | exc /32 | no-more \n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my @subnets;
    my @data = split(/\R/, $before);
    foreach (@data) {
        # subnet cidr is the first part before the comma and space
        my ($cidr, $rest) = split(/,\s+/);
        if ($cidr && $cidr =~ m/(\d{1,3}\.){3}\d{1,3}\/\d{1,2}/) {
              push(@subnets, $cidr);
        }
    }
    return @subnets;
}

1;


