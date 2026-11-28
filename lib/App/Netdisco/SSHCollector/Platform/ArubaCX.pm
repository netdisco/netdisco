package App::Netdisco::SSHCollector::Platform::ArubaCX;

=head1 NAME

App::Netdisco::SSHCollector::Platform::ArubaCX

=head1 DESCRIPTION

Collect ARP entries and IPv6 neighbors from ArubaCX devices, by VRF when
C<store_vrfs> is on, and connected subnets by VRF.

Every command is parsed as text: the AOS-CX CLI offers no structured form
(C<show running-config json> answers C<Invalid input: json>).

 device_auth:
   - tag: ssharubacx
     driver: cli
     platform: ArubaCX
     only: '192.0.2.1'
     username: oliver
     password: letmein

=cut

use strict;
use warnings;

use Dancer ':script';
use Moo;
use NetAddr::MAC qw/mac_as_ieee/;

use App::Netdisco::Util::VRF qw/netdisco_vrf/;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries and IPv6 neighbors from every VRF. C<$host> is the
hostname or IP address of the device. C<$ssh> is a Net::OpenSSH connection to
the device. Runs C<show arp all-vrfs> and C<show ipv6 neighbors all-vrfs>,
each on its own exec channel, and returns the rows read from each, whole or
not.

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

=item B<arpnip_by_vrf($host, $ssh, $args)>

As C<arpnip>, used when C<store_vrfs> is on, and reading IPv6 neighbors as
well. Runs C<show vrf>, C<show arp all-vrfs> and C<show ipv6 neighbors
all-vrfs>, each on its own exec channel, and names each entry's VRF from the
row's VRF column (C<default> is C<''>).

A table is read whole only when the command exited cleanly with no error
line, every line is a row, a header, a rule or the count, and the count it
prints equals the rows read. A whole table vouches for every VRF, because it
lists all of them: one absent from it has no entries. A family whose table is
not whole is left out of C<families>, and its rows are still returned.
C<show vrf> adds the VRFs that have no rows; when it fails, only the VRFs
named by rows are vouched and C<vrf_list_complete> is 0.

Returns C<< { entries => [ { ip, mac, vrf } ], vrf_read => { VRF => 1 },
vrf_list_complete => 0|1, families => [4, 6] } >>, or undef when neither
table was read whole.

Written against AOS-CX 10.16, where an account in the
C<operators> group can run all three commands and one in C<auditors> cannot.
No row with an empty MAC was captured, so a table holding one is not whole. A
table whose rows have no VRF column is not whole either, and those rows are
returned only by C<arpnip>.

=item B<subnets_by_vrf($host, $ssh, $args)>

Runs C<show ip route all-vrfs> and C<show ipv6 route all-vrfs> and returns the
connected (C<C>) routes of each VRF block, named as the device names them.
A table is used only when every line parsed and its route count matches; a
table that fails contributes nothing, and the other family's prefixes are
still returned.

Returns C<< { VRF => [ { prefix => '192.0.2.0', len => 24 }, ... ] } >>, or
undef when neither table was read whole. A VRF block with no connected route
maps to an empty list.

=back

=cut

my $MAC = qr/(?:[0-9a-f]{2}:){5}[0-9a-f]{2}/i;
my $RULE = qr/^-+\s*$/;

my @NEIGHBOR_TABLES = (
  { family => 4, command => 'show arp all-vrfs',
    header => qr/^IPv4 Address\s+MAC\b/,
    count  => qr/^Total Number Of ARP Entries Listed: (\d+)\.\s*$/ },
  { family => 6, command => 'show ipv6 neighbors all-vrfs',
    header => qr/^IPv6 Address\s+MAC\b/,
    count  => qr/^Total Number Of IPv6 Neighbors Entries Listed: (\d+)\.\s*$/ },
);

my @ROUTE_COMMANDS = ('show ip route all-vrfs', 'show ipv6 route all-vrfs');

sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;
    debug "$hostlabel $$ arpnip()";

    my @arpentries;
    foreach my $table (@NEIGHBOR_TABLES) {
        my ($rows, $whole, $error) = _neighbor_table($ssh, $table);
        info "$hostlabel $$ $error" unless $whole;
        push @arpentries, map { +{ ip => $_->{ip}, mac => $_->{mac} } } @$rows;
    }

    return @arpentries;
}

sub arpnip_by_vrf {
    my ($self, $hostlabel, $ssh, $args) = @_;
    debug "$hostlabel $$ arpnip_by_vrf()";

    my ($listed, $list_error) = _vrf_list($ssh);
    info "$hostlabel $$ $list_error, so VRFs without entries are not vouched"
      unless $listed;

    my (@entries, @families);
    foreach my $table (@NEIGHBOR_TABLES) {
        my ($rows, $whole, $error) = _neighbor_table($ssh, $table);
        push @entries, grep { defined $_->{vrf} } @$rows;
        if ($whole) { push @families, $table->{family} }
        else { info "$hostlabel $$ $error, so no VRF is vouched for IPv$table->{family}" }
    }
    return undef unless scalar @families;

    # each whole table lists every VRF, so a VRF absent from it has no entries
    my %vrf_read = map { ($_ => 1) } @{ $listed || [] }, map { $_->{vrf} } @entries;
    return { entries => \@entries, vrf_read => \%vrf_read,
             vrf_list_complete => ($listed ? 1 : 0), families => \@families };
}

sub subnets_by_vrf {
    my ($self, $hostlabel, $ssh, $args) = @_;
    debug "$hostlabel $$ subnets_by_vrf()";

    my (%subnets, $read_any);
    foreach my $command (@ROUTE_COMMANDS) {
        my ($routes, $error) = _route_table($ssh, $command);
        unless ($routes) {
            info "$hostlabel $$ $error, so it contributes nothing";
            next;
        }
        $read_any = 1;
        push @{ $subnets{$_} ||= [] }, @{ $routes->{$_} } for keys %$routes;
    }

    return $read_any ? \%subnets : undef;
}

# returns the output lines, or undef and why
sub _run {
    my ($ssh, $command) = @_;
    my @out = $ssh->capture($command);
    return (undef, "$command failed: " . $ssh->error) if $ssh->error;
    my @lines = map { s/\r?\n\z//r } @out;
    my ($error) = grep { m/^\s*(?:Invalid input|%)/ } @lines;
    return (undef, "$command returned an error: $error") if defined $error;
    return \@lines;
}

# returns the VRF names as netdisco stores them, or undef and why
sub _vrf_list {
    my ($ssh) = @_;
    my ($lines, $error) = _run($ssh, 'show vrf');
    return (undef, $error) unless $lines;
    return (undef, 'show vrf printed no VRF configuration')
      unless grep { m/^VRF Configuration:/ } @$lines;
    return [ map { m/^VRF Name\s*:\s*(\S+)\s*$/ ? netdisco_vrf($1) : () } @$lines ];
}

# returns the rows read, whether the table is whole, and why it is not
sub _neighbor_table {
    my ($ssh, $table) = @_;
    my ($lines, $error) = _run($ssh, $table->{command});
    return ([], 0, $error) unless $lines;

    my (@rows, $count, $unparsed);
    foreach my $line (@$lines) {
        next if $line =~ m/^\s*$/ or $line =~ $RULE or $line =~ $table->{header};
        if ($line =~ $table->{count}) { $count = $1; next }
        my $row = _neighbor_row($line);
        $row ? push(@rows, $row) : ++$unparsed;
    }

    my $command = $table->{command};
    my $unnamed = scalar grep { not defined $_->{vrf} } @rows;
    return (\@rows, 0, "$command printed $unparsed lines that are not rows") if $unparsed;
    return (\@rows, 0, "$command printed $unnamed rows without a VRF") if $unnamed;
    return (\@rows, 0, "$command printed no entry count") unless defined $count;
    return (\@rows, 0, sprintf '%s listed %d of %d entries', $command, scalar @rows, $count)
      unless $count == scalar @rows;
    return (\@rows, 1);
}

# IP, MAC, port, physical port, state, and VRF where the table has the column
sub _neighbor_row {
    my ($line) = @_;
    return unless $line =~ m/^([0-9a-f.:]+)\s+($MAC)\s+\S+\s+\S+\s+\S+(?:\s+(\S+))?\s*$/i;
    return { ip => lc $1, mac => mac_as_ieee($2), (defined $3 ? (vrf => netdisco_vrf($3)) : ()) };
}

# returns { VRF => [ { prefix, len } ] } of connected routes, or undef and why
sub _route_table {
    my ($ssh, $command) = @_;
    my ($lines, $error) = _run($ssh, $command);
    return (undef, $error) unless $lines;

    my (%routes, $vrf, $count, $listed, $unparsed);
    foreach my $line (@$lines) {
        if ($line =~ m/^VRF: (\S+)\s*$/) { $vrf = $1; $routes{$vrf} ||= []; next }
        if ($line =~ m/^Total Route Count : (\d+)\s*$/) { $count = $1; next }
        # the legend before the first VRF block
        next unless defined $vrf;
        next if $line =~ m/^\s*$/ or $line =~ $RULE
          or $line =~ m/^Prefix\s+Nexthop/ or $line =~ m/^\s+Type\s+Metric\s*$/;
        # another next hop of the route above
        next if $line =~ m/^\s+\S+\s+\S+\s+\S+\s+\[/;
        unless ($line =~ m{^(\S+)/(\d+)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\[}) { ++$unparsed; next }
        ++$listed;
        push @{ $routes{$vrf} }, { prefix => $1, len => $2 } if $3 eq 'C';
    }

    return (undef, "$command printed $unparsed lines that are not routes") if $unparsed;
    return (undef, "$command printed no route count") unless defined $count;
    return (undef, sprintf '%s listed %d of %d routes', $command, $listed // 0, $count)
      unless $count == ($listed // 0);
    return \%routes;
}

1;
