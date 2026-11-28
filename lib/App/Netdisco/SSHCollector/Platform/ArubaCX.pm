package App::Netdisco::SSHCollector::Platform::ArubaCX;

=head1 NAME

App::Netdisco::SSHCollector::Platform::ArubaCX

=head1 DESCRIPTION

Collect ARP entries and IPv6 neighbors from ArubaCX devices, by VRF when
C<store_vrfs> is on, and connected subnets by VRF.

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
use Expect;
use Moo;
use NetAddr::MAC qw/mac_as_ieee/;

use App::Netdisco::Util::VRF qw/netdisco_vrf/;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

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
No row with an empty MAC was captured, so a table holding one is not whole.

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

sub arpnip {

    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip()";

    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        debug "unable to run remote command [$hostlabel] " . $ssh->error;
        return ();
    }
    my $expect = Expect->init($pty);

    my ($pos, $error, $match, $before, $after);

    my $prompt = qr/#/;
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    $expect->send("no page\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    $expect->send("show arp all-vrfs\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);
    my @lines= split(m/\n/,$before);

    $expect->send("exit\n");
    $expect->soft_close();

    my @arpentries = ();

    # Example output from 'show arp':
    #
    # IPv4 Address     MAC                Port         Physical Port                                      State
    # -------------------------------------------------------------------------------------------------------------
    # a.b.c.d          aa:bb:cc:dd:ee:ff  vlanNN       1/1/1                                              reachable
    # ...
    #
    # Total Number Of ARP Entries Listed: 573.
    # -------------------------------------------------------------------------------------------------------------

    # pattern of the lines we are interested in:
    my $ip_patt = qr/(?:\d+\.\d+\.\d+\.\d+)/x;
    my $mac_patt = qr/(?:[0-9a-f]{2}:){5}[0-9a-f]{2}/x;
    my $linereg = qr/($ip_patt)\s+($mac_patt)\s+\S+\s+\S+/x;

    foreach my $line (@lines) {
        if ($line =~ $linereg) {
            my ($ip, $mac) = ($1, $2);
            push @arpentries, { mac => $mac, ip => $ip };
        }
    }

    return @arpentries;
}

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

sub arpnip_by_vrf {
    my ($self, $hostlabel, $ssh, $args) = @_;
    debug "$hostlabel $$ arpnip_by_vrf()";

    my ($listed, $list_error) = _vrf_list($ssh);
    info "$hostlabel $$ $list_error, so VRFs without entries are not vouched"
      unless $listed;

    my (@entries, @families);
    foreach my $table (@NEIGHBOR_TABLES) {
        my ($rows, $whole, $error) = _neighbor_table($ssh, $table);
        push @entries, @$rows;
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
    return (\@rows, 0, "$command printed $unparsed lines that are not rows") if $unparsed;
    return (\@rows, 0, "$command printed no entry count") unless defined $count;
    return (\@rows, 0, sprintf '%s listed %d of %d entries', $command, scalar @rows, $count)
      unless $count == scalar @rows;
    return (\@rows, 1);
}

# IP, MAC, port, physical port, state, VRF
sub _neighbor_row {
    my ($line) = @_;
    return unless $line =~ m/^([0-9a-f.:]+)\s+($MAC)\s+\S+\s+\S+\s+\S+\s+(\S+)\s*$/i;
    return { ip => lc $1, mac => mac_as_ieee($2), vrf => netdisco_vrf($3) };
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
