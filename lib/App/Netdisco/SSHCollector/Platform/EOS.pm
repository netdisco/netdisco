package App::Netdisco::SSHCollector::Platform::EOS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::EOS

=head1 DESCRIPTION

Collect ARP and IPv6 neighbor entries, MAC table, and connected subnet data
from Arista EOS devices.

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
IPv4 ARP and IPv6 neighbor entries from all VRFs are flattened into one list.

=item B<arpnip_by_vrf($host, $ssh, $args)>

As C<arpnip>, used when C<store_vrfs> is on. Names each entry's VRF from the
JSON key it appears under (C<default> is C<''>). A VRF is read whole only when
every command that returned usable JSON listed it with its neighbor table.

Returns C<< { entries => [ { ip, mac, vrf } ], vrf_read => { VRF => 0|1 },
vrf_list_complete => 0|1, families => [4, 6] } >>, or undef when neither
command returned usable JSON. C<families> names the address families
C<vrf_read> covers: C<[4]> or C<[6]> when only one command did (absent or
malformed would mean C<[4]>). IPv4 entries also carry C<iface>, as in
C<arpnip>; one with no interface is still returned, without C<iface>.

A subclass that overrides C<arpnip> must also override C<arpnip_by_vrf>, or
with C<store_vrfs> on this C<arpnip_by_vrf> is used instead of the override.

=item B<macsuck($host, $ssh)>

Retrieve MAC address table entries from device, skipping entries on the
C<Router> port. Returns a hashref in the format
C<< { VLAN => { PORT => { MACADDR => COUNT } } } >>.

=item B<subnets($host, $ssh)>

Retrieve directly connected IPv4 subnets from every VRF's routing table,
without host routes. Returns a list of CIDR strings such as C<10.1.1.0/24>.

=item B<subnets_by_vrf($host, $ssh, $args)>

As C<subnets>, used when C<store_vrfs> is on, and reading IPv6 as well. Runs
C<show ip route vrf all connected> and C<show ipv6 route vrf all connected>
and names each prefix's VRF from the JSON key it appears under (the worker
maps C<default> to C<''>).

Returns C<< { VRF => [ { prefix => '10.1.1.0', len => 24 }, ... ] } >>, or
undef when neither command returned usable JSON. A VRF with no connected routes
maps to an empty list. Host routes and link-local prefixes are returned as
EOS lists them: the worker filters them. A command that fails contributes
nothing and the other family's prefixes are still returned.

A subclass that overrides C<subnets> must also override C<subnets_by_vrf>, or
with C<store_vrfs> on this C<subnets_by_vrf> is used instead of the override.

=back

=cut

my $if_name_map = {
  Vl => "Vlan",
  Lo => "Loopback",
  Eth => "Ethernet",
  Po => "Port-channel",
};

my @ROUTE_COMMANDS = (
  { name => 'IPv4 route', command => "show ip route vrf all connected | json | no-more\n" },
  { name => 'IPv6 route', command => "show ipv6 route vrf all connected | json | no-more\n" },
);

my @NEIGHBOR_FAMILIES = (
  { name => 'ARP', family => 4, key => 'ipV4Neighbors', split_iface => 1,
    command => "show ip arp vrf all | json | no-more\n" },
  { name => 'IPv6 neighbor', family => 6, key => 'ipV6Neighbors', split_iface => 0,
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

    my (@entries, %listed, %seen, @families);
    foreach my $family (@NEIGHBOR_FAMILIES) {
        my ($vrfs, $error) = _neighbors_by_vrf($ssh, $family, 1);
        unless ($vrfs) {
            info "$hostlabel $$ $error, so no VRF is vouched for that family";
            next;
        }
        push @families, $family->{family};
        foreach my $vrf (sort { $a->[0] cmp $b->[0] } @$vrfs) {
            my $name = netdisco_vrf($vrf->[0]);
            ++$seen{$name};
            next unless $vrf->[1];
            ++$listed{$name};
            push @entries, map { +{ %$_, vrf => $name } } @{ $vrf->[1] };
        }
    }
    return undef unless scalar @families;

    my %vrf_read = map {
        ($_ => (($listed{$_} // 0) == scalar @families) ? 1 : 0)
    } keys %seen;

    # a command that decoded lists every VRF, so the list is whole for the
    # families read
    return { entries => \@entries, vrf_read => \%vrf_read, vrf_list_complete => 1,
             families => \@families };
}

# returns [ [VRF name as EOS gives it, [entries]], ... ] in hash order, or
# undef and why; a VRF without the family's neighbor list has undef entries
sub _neighbors_by_vrf {
    my ($ssh, $family, $keep_without_iface) = @_;

    my @out = $ssh->capture({ stdin_data => $family->{command} });
    return (undef, "error running $family->{name} command: " . $ssh->error)
      if $ssh->error;

    my $data = eval { decode_json(join '', @out) };
    return (undef, "failed to parse $family->{name} JSON")
      unless $data && $data->{vrfs};

    my @vrfs;
    foreach my $name (keys %{ $data->{vrfs} }) {
        my $neighbors = $data->{vrfs}->{$name}->{ $family->{key} };
        push @vrfs, [ $name, ($neighbors ? [ map { _neighbor_entries($family, $_, $keep_without_iface) } @$neighbors ] : undef) ];
    }
    return \@vrfs;
}

# arpnip drops an IPv4 neighbor with no interface, as it always has
sub _neighbor_entries {
    my ($family, $n, $keep_without_iface) = @_;
    return () unless $n->{address} && $n->{hwAddress};
    return { ip => $n->{address}, mac => $n->{hwAddress} } unless $family->{split_iface};

    # some entries have multiple interfaces: "Vlan3134, Port-Channel46"
    my @ifaces = split /\s*,\s*/, ($n->{interface} // '');
    return { ip => $n->{address}, mac => $n->{hwAddress} }
      if $keep_without_iface and not grep { $_ } @ifaces;
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

sub subnets_by_vrf {
    my ($self, $hostlabel, $ssh, $args) = @_;
    debug "$hostlabel $$ subnets_by_vrf()";

    my (%subnets, $read_any);
    foreach my $route (@ROUTE_COMMANDS) {
        my @out = $ssh->capture({ stdin_data => $route->{command} });
        if ($ssh->error) {
            info "$hostlabel $$ error running $route->{name} command: " . $ssh->error;
            next;
        }

        my $data = eval { decode_json(join '', @out) };
        unless ($data and ref {} eq ref $data and ref {} eq ref $data->{vrfs}) {
            info "$hostlabel $$ failed to parse $route->{name} JSON";
            next;
        }

        $read_any = 1;
        foreach my $vrf (keys %{ $data->{vrfs} }) {
            unless (length $vrf) {
                info "$hostlabel $$ $route->{name} table has a VRF with an empty name, so it contributes nothing";
                next;
            }
            my $table = $data->{vrfs}->{$vrf};
            my $routes = (ref {} eq ref $table) ? ($table->{routes} || {}) : undef;
            unless (ref {} eq ref $routes) {
                info "$hostlabel $$ $route->{name} table for VRF $vrf is not a hash, so it contributes nothing";
                next;
            }
            push @{ $subnets{$vrf} ||= [] }, map {
                my ($prefix, $len) = m{^(.+)/(\d+)$} ? ($1, $2) : ($_, undef);
                +{ prefix => $prefix, len => $len }
            } sort keys %$routes;
        }
    }

    return $read_any ? \%subnets : undef;
}

1;
