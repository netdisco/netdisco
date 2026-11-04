package App::Netdisco::SSHCollector::Platform::NXOS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::NXOS

=head1 DESCRIPTION

Collect ARP, MAC table, and connected subnet data from Cisco NXOS devices.

=cut

use strict;
use warnings;

use Dancer ':script';
use Moo;
use Expect;
use NetAddr::MAC qw/mac_as_ieee/;
use Regexp::Common 'net';
use JSON qw(decode_json);

use App::Netdisco::Util::VRF qw/netdisco_vrf/;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.
Entries from all VRFs are flattened into a single returned list.
Example:
C<< [ { ip => '192.0.2.10', mac => '0011.2233.4455' },
      { ip => '2001:db8::1', mac => 'aabb.ccdd.eeff' } ] >>.

=item B<arpnip_by_vrf($host, $ssh, $args)>

As C<arpnip>, used when C<store_vrfs> is on. Reads C<show vrf | json>, then
C<show ip arp vrf NAME | json> and C<show ipv6 neighbor vrf NAME | json> for
each listed VRF, all as exec requests, and names each entry's VRF from the
list (C<default> is C<''>). A VRF's family is read whole only when its reply
decodes, names the VRF asked for, and holds as many rows as its own count
(C<cnt-total> for ARP, C<count> for IPv6); rows without a MAC (C<INCOMPLETE>)
are skipped but count as rows. Link-local neighbors are kept.

Returns C<< { entries =E<gt> [ { ip, mac, vrf } ], vrf_read =E<gt> { VRF =E<gt> 0|1 },
vrf_list_complete =E<gt> 0|1, families =E<gt> [4, 6] } >>, or undef when
C<show vrf | json> fails or lists no VRF. A list row with no usable name makes
C<vrf_list_complete> 0. A VRF named C<all> is 0 and is never queried. A VRF is 1 only when both families
were read whole.

A subclass that overrides C<arpnip> must also override C<arpnip_by_vrf>, or
with C<store_vrfs> on this C<arpnip_by_vrf> is used instead of the override.

=item B<macsuck($host, $ssh)>

Retrieve MAC address table entries from device. C<$host> is the hostname or
IP address of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a hashref keyed by VLAN and interface, where leaf keys are MAC
addresses, in the format
C<< { VLAN => { PORT => { MACADDR => COUNT } } } >>.
Example:
C<< { 10 => { 'Ethernet1/1' => { '00:11:22:33:44:55' => 1 } },
      20 => { 'port-channel12' => { 'aa:bb:cc:dd:ee:ff' => 2 } } } >>.

=item B<subnets($host, $ssh)>

Retrieve directly connected IPv4 subnets from device routing tables. C<$host>
is the hostname or IP address of the device. C<$ssh> is a Net::OpenSSH
connection to the device.

Returns a list of IPv4 CIDR strings in the format C<< X.X.X.X/NN >>.
Example:
C<< [ '10.1.1.0/24', '192.0.2.0/25' ] >>.

=back

=cut

my $if_name_map = {
  Vl => "Vlan",
  Lo => "Loopback",
  Eth => "Ethernet",
  Po => "port-channel",
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

my $VRF_NAME = qr/\A[A-Za-z0-9_.:-]+\z/;

# exec requests, as macsuck sends them: no pty and no echo to parse
sub arpnip_by_vrf {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip_by_vrf()";

    my ($vrfs, $list_whole) = _listed_vrfs($hostlabel, $ssh);
    unless (scalar @$vrfs) {
        info "$hostlabel $$ show vrf | json did not return a VRF list, so VRF collection by CLI was skipped";
        return undef;
    }

    my (@entries, %vrf_read, %seen);
    foreach my $vrf (@$vrfs) {
        my $name = netdisco_vrf($vrf);
        my $whole = 1;
        foreach my $family (4, 6) {
            my $read = _read_family($hostlabel, $ssh, $vrf, $family);
            $whole = 0 unless $read->{whole};
            foreach my $entry (@{ $read->{entries} }) {
                next if $seen{ join '|', $name, @$entry{qw/ip mac/} }++;
                push @entries, { %$entry, vrf => $name };
            }
        }
        $vrf_read{$name} = $whole;
    }

    return { entries => \@entries, vrf_read => \%vrf_read,
             vrf_list_complete => $list_whole, families => [4, 6] };
}

# ([names in the order NX-OS lists them], list whole); no names when the list
# did not decode. A row that cannot be named leaves the list not whole, since
# the VRF behind it was never asked about.
sub _listed_vrfs {
    my ($hostlabel, $ssh) = @_;
    my $data = _json_reply($hostlabel, $ssh, 'show vrf | json') or return ([], 0);

    my (%seen, @names);
    my $whole = 1;
    foreach my $row (_as_list(eval { $data->{TABLE_vrf}->{ROW_vrf} })) {
        my $name = (ref {} eq ref $row ? $row->{vrf_name} : undef);
        if (not defined $name or ref $name or not length $name) { $whole = 0; next }
        push @names, $name unless $seen{lc $name}++;
    }
    return (\@names, $whole);
}

# a reply that is a JSON object, or undef; empty output is the unknown-name form
sub _json_reply {
    my ($hostlabel, $ssh, $command) = @_;
    my @out = $ssh->capture($command);
    if ($ssh->error) {
        debug "$hostlabel $$ error in SSH command [$command] " . $ssh->error;
        return undef;
    }
    my $data = eval { decode_json(join '', @out) };
    return (ref {} eq ref $data ? $data : undef);
}

# NX-OS gives a hash where a table has one row
sub _as_list {
    my $rows = shift;
    return (ref [] eq ref $rows ? @$rows : defined $rows ? ($rows) : ());
}

# the one hash under TABLE->{ROW}, or undef
sub _the_row {
    my ($table, $key) = @_;
    my @rows = _as_list(ref {} eq ref $table ? $table->{$key} : undef);
    return (1 == scalar @rows and ref {} eq ref $rows[0]) ? $rows[0] : undef;
}

# { whole => 0|1, entries => [...] }; whole needs a decoded reply for this VRF
# and as many rows as it counts. "all" is refused because its reply names
# itself and would pass for every VRF at once.
sub _read_family {
    my ($hostlabel, $ssh, $vrf, $family) = @_;
    my $unread = { whole => 0, entries => [] };
    my ($command, $count_key, $ip_key) = (4 == $family)
      ? ("show ip arp vrf $vrf | json | no-more", 'cnt-total', 'ip-addr-out')
      : ("show ipv6 neighbor vrf $vrf | json | no-more", 'count', 'ipv6-addr');

    return $unread unless $vrf =~ $VRF_NAME and lc $vrf ne 'all';
    my $data = _json_reply($hostlabel, $ssh, $command) or return $unread;

    my $vrf_row = _the_row($data->{TABLE_vrf}, 'ROW_vrf') or return $unread;
    return $unread unless defined $vrf_row->{'vrf-name-out'}
        and lc $vrf_row->{'vrf-name-out'} eq lc $vrf;

    my $holder = $vrf_row;
    if (6 == $family) {
        $holder = _the_row($vrf_row->{TABLE_afi}, 'ROW_afi') or return $unread;
        return $unread unless defined $holder->{afi} and $holder->{afi} eq 'ipv6';
    }
    my $count = $holder->{$count_key};
    return $unread unless defined $count and $count =~ m/\A\d+\z/;

    my @rows = grep { ref {} eq ref $_ }
               _as_list(ref {} eq ref $holder->{TABLE_adj} ? $holder->{TABLE_adj}->{ROW_adj} : undef);
    my @entries;
    foreach my $row (@rows) {
        my ($ip, $mac) = @$row{ $ip_key, 'mac' };
        next unless defined $ip and defined $mac and $mac =~ m/\A(?:[0-9a-f]{4}\.){2}[0-9a-f]{4}\z/i;
        push @entries, { ip => (6 == $family ? lc $ip : $ip), mac => mac_as_ieee($mac) };
    }

    return { whole => ($count == scalar @rows ? 1 : 0), entries => \@entries };
}

sub macsuck {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ macsuck()";
    # sent as an exec request: on stdin, NX-OS logs the session as a
    # configuration from vty (#1783)
    my @data = $ssh->capture("show mac address-table | no-more"); chomp @data;
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
