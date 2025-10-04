package App::Netdisco::SSHCollector::Platform::EOS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::EOS

=head1 DESCRIPTION

Collect ARP entries from Arista EOS devices.

=cut

use strict;
use warnings;

use Dancer ':script';
use Moo;
use NetAddr::MAC qw/mac_as_ieee/;
use JSON qw(decode_json);

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

    my @arpentries;

    # ----- IPv4 -----
    my $cmd_v4 = "show ip arp vrf all | json | no-more\n";
    my @out_v4 = $ssh->capture({ stdin_data => $cmd_v4 });
    if (!$ssh->error) {
        my $data = eval { decode_json(join '', @out_v4) };
        if ($data && $data->{vrfs}) {
            foreach my $vrf (values %{ $data->{vrfs} }) {
                next unless $vrf->{ipV4Neighbors};
                foreach my $n (@{ $vrf->{ipV4Neighbors} }) {
                    next unless $n->{address} && $n->{hwAddress};

                    # some entries have multiple interfaces: "Vlan3134, Port-Channel46"
                    my @ifaces = split /\s*,\s*/, ($n->{interface} // '');
                    foreach my $iface (@ifaces) {
                        push @arpentries, {
                            ip  => $n->{address},
                            mac => $n->{hwAddress},
                            ( $iface ? (iface => $iface) : () ),
                        };
                    }
                }
            }
        }
    } else {
        info "$hostlabel $$ error running ARP command: " . $ssh->error;
    }

    # ----- IPv6 -----
    my $cmd_v6 = "show ipv6 neighbor vrf all | json | no-more\n";
    my @out_v6 = $ssh->capture({ stdin_data => $cmd_v6 });
    if (!$ssh->error) {
        my $data = eval { decode_json(join '', @out_v6) };
        if ($data && $data->{vrfs}) {
            foreach my $vrf (values %{ $data->{vrfs} }) {
                next unless $vrf->{ipV6Neighbors};
                foreach my $n (@{ $vrf->{ipV6Neighbors} }) {
                    next unless $n->{address} && $n->{hwAddress};
                    push @arpentries, { ip => $n->{address}, mac => $n->{hwAddress} };
                }
            }
        }
    } else {
        info "$hostlabel $$ error running IPv6 neighbor command: " . $ssh->error;
    }

    return @arpentries;
}
sub macsuck {
    my ($self, $hostlabel, $ssh, $args) = @_;

    unless ($ssh) {
        info "$hostlabel $$ macsuck() - no SSH session";
        return;
    }

    debug "$hostlabel $$ macsuck()";

    my $cmd = "show mac address-table | json | no-more\n";
    my @out = $ssh->capture({ stdin_data => $cmd });
    if ($ssh->error) {
        info "$hostlabel $$ error running command: " . $ssh->error;
        return;
    }

    my $json = join '', @out;
    my $data = eval { decode_json($json) };
    if ($@ or not $data->{unicastTable}->{tableEntries}) {
        info "$hostlabel $$ failed to parse JSON: $@";
        return;
    }

    my $macentries = {};

    foreach my $entry (@{ $data->{unicastTable}->{tableEntries} }) {
        my $vlan = $entry->{vlanId} // 0;
        my $mac  = mac_as_ieee($entry->{macAddress});
        my $port = $entry->{interface};

        # Skip bogus/no-port entries
        next unless $mac && $port && $port ne 'Router';


        ++$macentries->{$vlan}->{$port}->{$mac};

        debug sprintf "Parsed MAC vlan=%s mac=%s port=%s type=%s",
            $vlan, $mac, $port, $entry->{entryType};
    }

    return $macentries;
}

sub subnets {
    my ($self, $hostlabel, $ssh, $args) = @_;
    debug "$hostlabel $$ subnets()";

    my $cmd = "show ip route vrf all connected | json | no-more\n";
    my @out = $ssh->capture({ stdin_data => $cmd });
    if ($ssh->error) {
        info "$hostlabel $$ error running route command: " . $ssh->error;
        return;
    }

    my $data = eval { decode_json(join '', @out) };
    if ($@ or not $data->{vrfs}) {
        info "$hostlabel $$ failed to parse JSON routes: $@";
        return;
    }

    my @subnets;
    foreach my $vrf (values %{ $data->{vrfs} }) {
        foreach my $cidr (keys %{ $vrf->{routes} }) {
            next if $cidr =~ m/\/32$/; # skip host routes
            push @subnets, $cidr if $cidr =~ m{^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$};
        }
    }

    return @subnets;
}

1;
