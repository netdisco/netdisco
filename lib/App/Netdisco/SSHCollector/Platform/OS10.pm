package App::Netdisco::SSHCollector::Platform::OS10;

=head1 NAME

App::Netdisco::SSHCollector::Platform::OS10

=head1 DESCRIPTION

Collect ARP entries from Dell OS10 devices.

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

    # $Expect::Debug = 1;
    # $Expect::Exp_Internal = 1;

    my $expect = Expect->init($pty);
    $expect->raw_pty(1);

    my ($pos, $error, $match, $before, $after);
    my $prompt = qr/# +$/;
    my $timeout = 60;

    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    # Get all VRFs, skip header line
    $expect->send("show ip vrf | except VRF-Name | no-more \n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
    my @vrfs = split(/\R/, $before);

    # Regex for VRF name
    my $vrf_re = qr/^([a-z\-_0-9\.]+)\s+.+$/i;

    # IP ARP match
    my $iparp_re = qr/^((\d{1,3}\.){3}\d{1,3})\s*(([0-9a-f]{2}[:-]){5}[0-9a-f]{2})\s+.+$/i;

    # Will hold results
    my @arpentries;

    foreach my $vrf_line (@vrfs) {
        my $vrf_name ;
        # Get the VRF name
        if ($vrf_line && $vrf_line =~ m/$vrf_re/) {
            $vrf_name = $1;
        } else {
            next ;
        }
        # Get IP ARP entries for this VRF
        my $vrf_cmd = sprintf("show ip arp vrf %s | no-more \n", $vrf_name) ;
        $expect->send($vrf_cmd);
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
        my @iparps = split(/\R/, $before);

        foreach my $iparp_line (@iparps) {
            if($iparp_line && $iparp_line =~ m/$iparp_re/) {
                push(@arpentries, { ip => $1, mac => $3 });
            }
        }
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
    # VlanId        Mac Address         Type        Interface
    # 54            00:00:5e:00:01:36   dynamic     port-channel1
    # 54            00:50:56:af:12:f5   dynamic     port-channel1
    # 54            00:50:56:af:ca:a3   dynamic     port-channel1
    # 54            04:09:73:e3:22:40   dynamic     port-channel17
    
    my $re_mac_line = qr/^(\d+)\s+((([0-9a-f]{2}[:-]){5})[0-9a-f]{2})\s+\w+\s+([a-z]+.*)$/i;
    my $macentries = {};

    foreach my $line (@data) {
        if ($line && $line =~ m/$re_mac_line/) {
            my $port = $5;
            my $vlan = $1;

            ++$macentries->{$vlan}->{$port}->{mac_as_ieee($2)};
        }
    }

    return $macentries;
}

1;


