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

use App::Netdisco::Util::VRF qw/netdisco_vrf/;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.

=item B<arpnip_by_vrf($host, $ssh, $args)>

As C<arpnip>, used when C<store_vrfs> is on. Names each entry's VRF from the
JSON key it appears under (C<default> is C<''>). A VRF is read whole only when
both the ARP and the IPv6 neighbor command listed it with its neighbor table.

Returns C<< { entries => [ { ip, mac, vrf } ], vrf_read => { VRF => 0|1 },
vrf_list_complete => 0|1, families => [4, 6] } >> (C<families> names the
address families C<vrf_read> covers; absent means C<[4, 6]>), or undef
when neither command returned usable JSON. IPv4 entries also carry
C<iface>, as in C<arpnip>.

=back

=cut

my $if_name_map = {
  Vl => "Vlan",
  Lo => "Loopback",
  Eth => "Ethernet",
  Po => "Port-channel",
};

my @NEIGHBOR_FAMILIES = (
  { name => 'ARP', key => 'ipV4Neighbors', split_iface => 1,
    command => "show ip arp vrf all | json | no-more\n" },
  { name => 'IPv6 neighbor', key => 'ipV6Neighbors', split_iface => 0,
    command => "show ipv6 neighbor vrf all | json | no-more\n" },
);

sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;
    debug "$hostlabel $$ arpnip()";

    my @arpentries;
    foreach my $family (@NEIGHBOR_FAMILIES) {
        my ($vrfs, $error) = _neighbors_by_vrf($ssh, $family);
        # arpnip has only ever logged the SSH error, not unparsed JSON
        info "$hostlabel $$ $error" if $ssh->error;
        push @arpentries, map { @{ $_->[1] || [] } } @{ $vrfs || [] };
    }

    return @arpentries;
}

sub arpnip_by_vrf {
    my ($self, $hostlabel, $ssh, $args) = @_;
    debug "$hostlabel $$ arpnip_by_vrf()";

    my (@entries, %listed, %seen);
    my $families_read = 0;
    foreach my $family (@NEIGHBOR_FAMILIES) {
        my ($vrfs, $error) = _neighbors_by_vrf($ssh, $family);
        unless ($vrfs) {
            info "$hostlabel $$ $error, so no VRF is read whole";
            next;
        }
        ++$families_read;
        foreach my $vrf (sort { $a->[0] cmp $b->[0] } @$vrfs) {
            my $name = netdisco_vrf($vrf->[0]);
            ++$seen{$name};
            next unless $vrf->[1];
            ++$listed{$name};
            push @entries, map { +{ %$_, vrf => $name } } @{ $vrf->[1] };
        }
    }
    return undef unless $families_read;

    my $whole = ($families_read == scalar @NEIGHBOR_FAMILIES) ? 1 : 0;
    my %vrf_read = map {
        ($_ => ($whole and ($listed{$_} // 0) == scalar @NEIGHBOR_FAMILIES) ? 1 : 0)
    } keys %seen;

    return { entries => \@entries, vrf_read => \%vrf_read, vrf_list_complete => $whole,
             families => [4, 6] };
}

# returns [ [VRF name as EOS gives it, [entries]], ... ] in hash order, or
# undef and why; a VRF without the family's neighbor list has undef entries
sub _neighbors_by_vrf {
    my ($ssh, $family) = @_;

    my @out = $ssh->capture({ stdin_data => $family->{command} });
    return (undef, "error running $family->{name} command: " . $ssh->error)
      if $ssh->error;

    my $data = eval { decode_json(join '', @out) };
    return (undef, "failed to parse $family->{name} JSON")
      unless $data && $data->{vrfs};

    my @vrfs;
    foreach my $name (keys %{ $data->{vrfs} }) {
        my $neighbors = $data->{vrfs}->{$name}->{ $family->{key} };
        push @vrfs, [ $name, ($neighbors ? [ map { _neighbor_entries($family, $_) } @$neighbors ] : undef) ];
    }
    return \@vrfs;
}

sub _neighbor_entries {
    my ($family, $n) = @_;
    return () unless $n->{address} && $n->{hwAddress};
    return { ip => $n->{address}, mac => $n->{hwAddress} } unless $family->{split_iface};

    # some entries have multiple interfaces: "Vlan3134, Port-Channel46"
    my @ifaces = split /\s*,\s*/, ($n->{interface} // '');
    return map {
        +{ ip => $n->{address}, mac => $n->{hwAddress}, ( $_ ? (iface => $_) : () ) }
    } @ifaces;
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
