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
sends the C<show ip arp vrf NAME | json> and C<show ipv6 neighbor vrf NAME |
json> commands of the listed VRFs chained with C<;>, at most 16 commands and
640 bytes per exec request, and names each entry's VRF from the list
(C<default> is C<''>). Each reply document is assigned by its own VRF name and
table shape, not its position. A VRF's family is read whole only when exactly
one document for it decodes and holds as many rows as its own count
(C<cnt-total> for ARP, C<count> for IPv6); a request that fails, or a document
that does not decode, leaves the VRF and families after it unread. VRF names
that differ only in case are all 0 and never queried, and make
C<vrf_list_complete> 0. Rows without a MAC (C<INCOMPLETE>) are skipped but
count as rows. Link-local neighbors are kept.

Returns C<< { entries =E<gt> [ { ip, mac, vrf } ], vrf_read =E<gt> { VRF =E<gt> 0|1 },
vrf_list_complete =E<gt> 0|1, families =E<gt> [4, 6] } >>, or undef when
C<show vrf | json> fails or lists no VRF. A list row with no usable name, or a
list without C<default>, makes C<vrf_list_complete> 0; the global table is read
either way. A VRF named C<all> is 0 and is never queried. A VRF is 1 only when
both families were read whole.

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

=item B<subnets_by_vrf($host, $ssh, $args)>

As C<subnets>, used when C<store_vrfs> is on, and reading IPv6 as well. Sends
C<show ip route direct vrf all | json> and C<show ipv6 route direct vrf all |
json>, each as one exec request (no pty), and names each prefix's VRF from
C<vrf-name-out> (the worker maps C<default> to C<''>). C<direct> lists only
connected and local-direct routes, so no default or learned route is returned,
but host routes (C</32>, C</128>) are: the worker filters them. VRF names, such
as C<egress-loadbalance-resolution->, are passed through as the device prints
them. Where NX-OS prints a hash for a one-row table, it is read as a list of
one.

Returns C<< { VRF =E<gt> [ { prefix =E<gt> '10.1.1.0', len =E<gt> 24 }, ... ] } >>, or
undef when neither command returned usable JSON. A VRF with no connected routes
is absent. A command that fails contributes nothing and the other family's
prefixes are still returned. A failure is an SSH error (including a non-zero
exit, which a C<Syntax error> reply gives), a reply that does not decode, or a
reply that is not the expected table. Some images leave the exec channel open
after a complete reply; that costs the SSH inactivity timeout and that family.

A subclass that overrides C<subnets> must also override C<subnets_by_vrf>, or
with C<store_vrfs> on this C<subnets_by_vrf> is used instead of the override.

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
my $COMMANDS_PER_REQUEST = 16;
# the live device ran a 676 byte command line; stay under what is proven
my $BYTES_PER_REQUEST = 640;

# exec requests, as macsuck sends them: no pty and no echo to parse. Each
# exec costs a round trip, so the per-VRF commands share requests, chained
# with " ; ": NX-OS prints one JSON document per command, in order.
sub arpnip_by_vrf {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip_by_vrf()";

    my ($vrfs, $list_whole, $ambiguous) = _listed_vrfs($hostlabel, $ssh);
    unless (scalar @$vrfs) {
        info "$hostlabel $$ show vrf | json did not return a VRF list, so VRF collection by CLI was skipped";
        return undef;
    }

    # "all" is refused because its reply names itself and would pass for
    # every VRF at once
    my @askable = grep { $_ =~ $VRF_NAME and lc $_ ne 'all' and not $ambiguous->{$_} } @$vrfs;
    my %reads;
    foreach my $chunk (_request_chunks(@askable)) {
        %reads = (%reads, _read_chained($hostlabel, $ssh, $chunk));
    }

    my (@entries, %vrf_read, %seen);
    foreach my $vrf (@$vrfs) {
        my $name = netdisco_vrf($vrf);
        my $whole = 1;
        foreach my $family (4, 6) {
            my $read = $reads{$vrf}->{$family} || { whole => 0, entries => [] };
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

# ([names in the order NX-OS lists them], list whole, { names ambiguous by
# case }); no names when the list did not decode. A row that cannot be named,
# a list without "default", or names that differ only in case (NX-OS show
# commands ignore case, so neither could be read unambiguously) leave the
# list not whole.
sub _listed_vrfs {
    my ($hostlabel, $ssh) = @_;
    my $data = _json_reply($hostlabel, $ssh, 'show vrf | json') or return ([], 0, {});

    my (%seen, @names, %spellings);
    my $whole = 1;
    foreach my $row (_as_list(eval { $data->{TABLE_vrf}->{ROW_vrf} })) {
        my $name = (ref {} eq ref $row ? $row->{vrf_name} : undef);
        if (not defined $name or ref $name or not length $name) { $whole = 0; next }
        next if $seen{$name}++;
        push @names, $name;
        push @{ $spellings{lc $name} }, $name;
    }
    my %ambiguous = map { ($_ => 1) } map { @$_ } grep { 1 < scalar @$_ } values %spellings;
    $whole = 0 if scalar %ambiguous;
    # the global table is always read; a list that hides it cannot vouch for it
    if (@names and not grep { $_ eq 'default' } @names) {
        push @names, 'default';
        $whole = 0;
    }
    return (\@names, $whole, \%ambiguous);
}

# lists of VRF names, each small enough for one chained request
sub _request_chunks {
    my @names = @_;
    my (@chunks, @current);
    foreach my $name (@names) {
        my $with = [ @current, $name ];
        if (@current and (2 * @$with > $COMMANDS_PER_REQUEST
                          or length(_chain_command(@$with)) > $BYTES_PER_REQUEST)) {
            push @chunks, [ @current ];
            @current = ();
        }
        push @current, $name;
    }
    push @chunks, \@current if @current;
    return @chunks;
}

sub _chain_command {
    return join ' ; ', map {
        ("show ip arp vrf $_ | json | no-more", "show ipv6 neighbor vrf $_ | json | no-more")
    } @_;
}

# one exec request for the ARP and neighbor commands of these VRFs; returns
# (VRF => { 4 => read, 6 => read }). Each document is assigned by what it
# says (its VRF and its table shape), never by its position, so a missing or
# reordered document cannot shift another VRF's rows onto it. A (VRF, family)
# without exactly one document is unread.
sub _read_chained {
    my ($hostlabel, $ssh, $vrfs) = @_;
    my %asked = map { (lc $_ => $_) } @$vrfs;
    my $command = _chain_command(@$vrfs);

    my @out = $ssh->capture($command);
    if ($ssh->error) {
        debug "$hostlabel $$ error in SSH command [$command] " . $ssh->error;
        return ();
    }

    my (%documents, %reads);
    foreach my $data (_json_documents(join '', @out)) {
        my ($vrf_row, $family) = _document_identity($data);
        my $vrf = (defined $vrf_row ? $asked{ lc($vrf_row->{'vrf-name-out'} // '') } : undef);
        unless (defined $vrf and $family) {
            debug "$hostlabel $$ ignoring a document that answers no command asked";
            next;
        }
        push @{ $documents{$vrf}->{$family} }, $vrf_row;
    }
    foreach my $vrf (keys %documents) {
        foreach my $family (keys %{ $documents{$vrf} }) {
            my $rows = $documents{$vrf}->{$family};
            $reads{$vrf}->{$family} = _family_read($rows->[0], $family) if 1 == scalar @$rows;
        }
    }
    return %reads;
}

# the documents of a stream, up to the first one that does not decode
sub _json_documents {
    my $text = shift;
    my $parser = JSON->new;
    $parser->incr_parse($text);
    my @documents;
    while (1) {
        my $data = eval { $parser->incr_parse };
        last unless defined $data;
        push @documents, $data if ref {} eq ref $data;
    }
    return @documents;
}

# (the ROW_vrf hash, 4 or 6), or nothing when the document is neither table
sub _document_identity {
    my $data = shift;
    my $vrf_row = _the_row($data->{TABLE_vrf}, 'ROW_vrf') or return ();
    return ($vrf_row, 6) if exists $vrf_row->{TABLE_afi};
    return ($vrf_row, 4) if exists $vrf_row->{'cnt-total'};
    return ();
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

# { whole => 0|1, entries => [...] } from one document's ROW_vrf; whole needs
# as many rows as the document counts
sub _family_read {
    my ($vrf_row, $family) = @_;
    my $unread = { whole => 0, entries => [] };
    my ($count_key, $ip_key) = (4 == $family) ? ('cnt-total', 'ip-addr-out') : ('count', 'ipv6-addr');

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
            my $port = exists $if_name_map->{$5} ? $if_name_map->{$5} . ($6 || '') : $4;
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

my @ROUTE_COMMANDS = (
  { name => 'IPv4 route', command => 'show ip route direct vrf all | json' },
  { name => 'IPv6 route', command => 'show ipv6 route direct vrf all | json' },
);

sub subnets_by_vrf {
    my ($self, $hostlabel, $ssh, $args) = @_;
    debug "$hostlabel $$ subnets_by_vrf()";

    my (%subnets, $read_any);
    foreach my $route (@ROUTE_COMMANDS) {
        my @out = $ssh->capture($route->{command});
        if ($ssh->error) {
            info "$hostlabel $$ error running $route->{name} command: " . $ssh->error;
            next;
        }

        my $data = eval { decode_json(join '', @out) };
        unless (ref {} eq ref $data and ref {} eq ref $data->{TABLE_vrf}) {
            info "$hostlabel $$ failed to parse $route->{name} JSON";
            next;
        }

        $read_any = 1;
        foreach my $vrf_row (_rows($data->{TABLE_vrf}, 'ROW_vrf')) {
            my $name = $vrf_row->{'vrf-name-out'};
            # an unnamable row must not be filed as a junk VRF or the global table
            next if not defined $name or ref $name or not length $name;
            my @prefixes = _row_prefixes($vrf_row);
            push @{ $subnets{$name} }, @prefixes if scalar @prefixes;
        }
    }

    return $read_any ? \%subnets : undef;
}

# the hash rows under TABLE->{ROW}, however many the device printed
sub _rows {
    my ($table, $key) = @_;
    return grep { ref {} eq ref $_ } _as_list(ref {} eq ref $table ? $table->{$key} : undef);
}

# every connected prefix under one ROW_vrf, across its address families
sub _row_prefixes {
    my $vrf_row = shift;
    my @prefixes;
    foreach my $addrf (_rows($vrf_row->{TABLE_addrf}, 'ROW_addrf')) {
        foreach my $row (_rows($addrf->{TABLE_prefix}, 'ROW_prefix')) {
            my $cidr = $row->{ipv6prefix} // $row->{ipprefix};
            next unless defined $cidr and not ref $cidr;
            my ($prefix, $len) = $cidr =~ m{^(.+)/(\d+)$} ? ($1, $2) : ($cidr, undef);
            push @prefixes, { prefix => $prefix, len => $len };
        }
    }
    return @prefixes;
}

1;
