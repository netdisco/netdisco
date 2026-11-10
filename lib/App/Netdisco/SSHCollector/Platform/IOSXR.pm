package App::Netdisco::SSHCollector::Platform::IOSXR;

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOSXR

=head1 DESCRIPTION

Collect ARP entries from Cisco IOS-XR routers using Expect, and, with
C<store_vrfs> on, IPv6 neighbor entries as well. Suitable for both 32- and
64-bit IOS-XR.

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use NetAddr::MAC qw/mac_as_ieee/;
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

=item B<arpnip_by_vrf($host, $ssh, $args)>

As C<arpnip>, used when C<store_vrfs> is on. Reads C<show vrf all>, then the
global C<show arp> and C<show ipv6 neighbors> and, for each listed VRF,
C<show arp vrf NAME> and, when the global C<show ipv6 neighbors> answered,
C<show ipv6 neighbors vrf NAME>. Each entry's VRF is the one it was read from
(the global table is C<''>). The global C<show ipv6 neighbors> also lists
VRF neighbors, so its entries carry C<< mixed => 1 >>. The router's own
addresses (state C<Interface>) are kept, as C<arpnip> keeps them.

Returns C<{ entries =E<gt> [ { ip, mac, vrf } ], vrf_read =E<gt> { VRF =E<gt> 0|1 },
vrf_list_complete =E<gt> 0|1, families =E<gt> [4, 6] }>, or undef when the
session or C<show vrf all> fails. C<families> is C<[4]> when the global
C<show ipv6 neighbors> did not answer cleanly (IPv6 is unsupported or
unreached), and then C<vrf_read> covers IPv4 only; otherwise it is C<[4, 6]>.
A table is read whole when it returned to the prompt with no C<%> or
C<Invalid> line and every line was a timestamp, a header, a location, an
entry or a multicast adjacency. A VRF is 1 only when its table for every
family in C<families> was read whole, so a VRF whose IPv6 table fails is 0
though its IPv4 entries are reported. A VRF that is empty, misspelled or
unknown prints nothing, so an empty table reads as whole. A VRF list row
that cannot be parsed into a name makes C<vrf_list_complete> 0, and a VRF
name outside C<[A-Za-z0-9_.:-]> or equal to C<all> is 0 with no command sent.
Only a VRF named exactly C<default> is skipped as the global table; C<Default>
is a user VRF. A C<show vrf all> that returned with its header and no VRF is a whole, empty
list. After a timeout the rest of the session is not read, and that VRF and
every one not yet read are 0.

A subclass that overrides C<arpnip> must also override C<arpnip_by_vrf>, or
with C<store_vrfs> on this C<arpnip_by_vrf> is used instead of the override.

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
    my $expect = Expect->init($pty);

    my ($pos, $error, $match, $before, $after);
    my $prompt = qr/# +$/;
    my $timeout = 10;

    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    $expect->send("terminal length 0\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    $expect->send("show arp vrf all\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my @arpentries = ();
    my @data = split(m/\n/, $before);

    foreach (@data) {
        my ($ip, $age, $mac, $state, $t, $iface) = split(/\s+/);

        if ($ip =~ m/(\d{1,3}\.){3}\d{1,3}/
            && $mac =~ m/([0-9a-f]{4}\.){2}[0-9a-f]{4}/i) {
              push(@arpentries, { ip => $ip, mac => $mac });
        }
    }


    $expect->send("exit\n");
    $expect->hard_close();

    return @arpentries;
}

# the prompt alone at the end of the output, so a row never ends a read
my $VRF_PROMPT = qr/^[^\s#]+#\s*\z/m;

my $VRF_NAME    = qr/\A[A-Za-z0-9_.:-]+\z/;
my $TIMESTAMP   = qr/^\s*[A-Z][a-z]{2}\s+[A-Z][a-z]{2}\s+\d+\s+\d\d:\d\d:\d\d(?:\.\d+)?\s+\S+\s*$/;
my $DASHES      = qr/^\s*-{5,}\s*$/;
my $LOCATION    = qr{^\s*\d+(?:/\w+)+\s*$};
my $VRF_HEADER  = qr/^\s*VRF\s+RD\s+RT\s+AFI\s+SAFI\b/;
my $IPV4_HEADER = qr/^\s*Address\s+Age\s+Hardware Addr/i;
my $IPV6_HEADER = qr/^\s*IPv6 Address\s+Age\s+Link-layer/i;
my $MAC_DOTTED  = qr/[0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}/i;
my $ERROR_LINE  = qr/^\s*(?:%|Invalid)/;

sub arpnip_by_vrf {
    my ($self, $hostlabel, $ssh, $args) = @_;
    debug "$hostlabel $$ arpnip_by_vrf()";

    my ($exp, $timeout) = _open_vrf_session($hostlabel, $ssh, $args) or return undef;

    my $list = _run_command($exp, $timeout, 'show vrf all');
    my ($vrfs, $names_whole, $list_whole) = _parse_vrf_list($list);
    unless ($list_whole) {
        info "$hostlabel $$ arpnip_by_vrf() show vrf all did not return a VRF list, so VRF collection by CLI was skipped";
        _close_vrf_session($exp);
        return undef;
    }

    my $state = { entries => [], seen => {}, whole => {}, unread => {}, timed_out => 0 };
    my $ipv6_answers = 0;
    my @plan = ([ '', 4, 'show arp' ], [ '', 6, 'show ipv6 neighbors' ]);
    while (my $step = shift @plan) {
        my ($vrf, $family, $command) = @$step;
        my $errored = _read_table($hostlabel, $state, $exp, $timeout, $vrf, $family, $command);
        if ($family == 6 and $vrf eq '') {
            $ipv6_answers = !$errored;
            push @plan, map { _vrf_steps($hostlabel, $_, $ipv6_answers, $state) } @$vrfs;
        }
        if ($state->{timed_out}) {
            info "$hostlabel $$ arpnip_by_vrf() [$command] timed out, so nothing after it was read";
            last;
        }
    }
    _close_vrf_session($exp);

    my @families = ($ipv6_answers ? (4, 6) : (4));
    my %vrf_read = map {
        my $vrf = $_;
        ($vrf => ((!$state->{unread}->{$vrf} and 0 == grep { !$state->{whole}->{$vrf}->{$_} } @families) ? 1 : 0))
    } ('', @$vrfs);

    return {
        entries => $state->{entries}, vrf_read => \%vrf_read,
        vrf_list_complete => (($state->{timed_out} or !$names_whole) ? 0 : 1),
        families => \@families,
    };
}

# the commands for one VRF; a name that is not plain is never sent, since it
# could carry a second command, and "all" would answer for every VRF at once
sub _vrf_steps {
    my ($hostlabel, $vrf, $ipv6_answers, $state) = @_;
    unless ($vrf =~ $VRF_NAME and lc $vrf ne 'all') {
        debug "$hostlabel $$ arpnip_by_vrf() VRF name [$vrf] is not usable in a command, so it was not read";
        $state->{unread}->{$vrf} = 1;
        return ();
    }
    my @steps = ([ $vrf, 4, "show arp vrf $vrf" ]);
    push @steps, [ $vrf, 6, "show ipv6 neighbors vrf $vrf" ] if $ipv6_answers;
    return @steps;
}

# (names, whether every row gave a name, whether this is a whole VRF list).
# The global table is not listed ("default" is skipped should a build list it,
# but only that exact name, since a complete list retires the VRFs it leaves
# out); an indented line continues the row above and holds no name.
sub _parse_vrf_list {
    my ($text) = @_;
    return ([], 0, 0) unless defined $text;

    my (@names, %seen);
    my ($header, $errored, $names_whole, $rows) = (0, 0, 1, 0);
    foreach my $line (split /\r?\n/, $text) {
        next if $line =~ m/^\s*$/ or $line =~ $TIMESTAMP;
        if ($line =~ $ERROR_LINE) { $errored = 1; next }
        if ($line =~ $VRF_HEADER) { $header = 1; next }
        if ($line =~ m/^\s/) { $names_whole = 0 unless $rows; next }
        unless ($line =~ m/^(\S+)\s+\S/) { $names_whole = 0; next }
        $rows++;
        my $name = $1;
        push @names, $name unless $name eq 'default' or $seen{$name}++;
    }

    return (\@names, $names_whole, ($header and !$errored) ? 1 : 0);
}

# returns the Expect session once the pager is off, and the timeout, or nothing
sub _open_vrf_session {
    my ($hostlabel, $ssh, $args) = @_;

    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        warn "unable to run remote command [$hostlabel] " . $ssh->error;
        return;
    }

    my $exp = Expect->init($pty);
    $exp->raw_pty(1);
    my $timeout = ($args && $args->{timeout}) ? $args->{timeout} : 30;

    my ($pos) = $exp->expect($timeout, -re => $VRF_PROMPT);
    # width 0 keeps a long command from scrolling the echo, which would spoil the read
    unless ($pos and defined _run_command($exp, $timeout, 'terminal length 0')
            and defined _run_command($exp, $timeout, 'terminal width 0')) {
        info "$hostlabel $$ arpnip_by_vrf() unable to reach CLI prompt";
        $exp->hard_close();
        return;
    }

    return ($exp, $timeout);
}

sub _close_vrf_session {
    my $exp = shift;
    $exp->send("exit\n");
    $exp->hard_close();
}

# the command's output without the echoed command, or undef on a timeout,
# after which Expect still holds the partial output
sub _run_command {
    my ($exp, $timeout, $command) = @_;

    $exp->send("$command\n");
    my ($pos, undef, undef, $before) = $exp->expect($timeout, -re => $VRF_PROMPT);
    return undef unless $pos;

    my @lines = split /\r?\n/, ($before // '');
    shift @lines if @lines and $lines[0] =~ m/^\s*\Q$command\E\s*$/;
    return join "\n", @lines;
}

# runs one command and records its entries and whether it was read whole;
# returns true when the device answered with an error or timed out
sub _read_table {
    my ($hostlabel, $state, $exp, $timeout, $vrf, $family, $command) = @_;

    my $output = _run_command($exp, $timeout, $command);
    unless (defined $output) {
        debug "$hostlabel $$ arpnip_by_vrf() command [$command] failed: no prompt within ${timeout}s";
        $state->{timed_out} = 1;
        $state->{unread}->{$vrf} = 1;
        return 1;
    }

    my ($entries, $whole, $errored) = _parse_table($output, $family);
    debug "$hostlabel $$ arpnip_by_vrf() command [$command] returned an error" if $errored;
    foreach my $entry (@$entries) {
        my $key = lc join '|', $vrf, @$entry{qw/ip mac/};
        next if $state->{seen}->{$key}++;
        # the global show ipv6 neighbors also lists VRF neighbors
        my @mixed = (($vrf eq '' and $family == 6) ? (mixed => 1) : ());
        push @{ $state->{entries} }, { %$entry, vrf => $vrf, @mixed };
    }
    $state->{whole}->{$vrf}->{$family} = $whole;
    return $errored;
}

# returns the entries, whether every line was a known non-row or an entry,
# and whether an error line was seen
sub _parse_table {
    my ($output, $family) = @_;
    my ($header, $row) = ($family == 4
        ? ($IPV4_HEADER, \&_parse_arp_row) : ($IPV6_HEADER, \&_parse_neighbor_row));
    my (@entries, $errored);
    my $whole = 1;

    foreach my $line (split /\r?\n/, $output) {
        next if $line =~ m/^\s*$/ or $line =~ $TIMESTAMP or $line =~ $DASHES
            or $line =~ $LOCATION or $line =~ $header;
        if ($line =~ $ERROR_LINE) { $errored = 1; $whole = 0; next }
        my ($recognized, $entry) = $row->($line);
        $whole = 0 unless $recognized;
        push @entries, $entry if $entry;
    }

    return (\@entries, $whole, $errored);
}

# returns whether the line is a row, and its entry unless the row is incomplete
sub _parse_arp_row {
    my ($line) = @_;
    return (0) unless $line =~ m/^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+\S+\s+($MAC_DOTTED)\s+(\S+)\s+\S+\s+\S+\s*$/;
    my ($ip, $mac, $state) = ($1, $2, $3);
    return (1, (lc $state eq 'incomplete' ? undef : { ip => $ip, mac => mac_as_ieee($mac) }));
}

# "[Mcast adjacency]" rows carry no host and a zero MAC on every interface
sub _parse_neighbor_row {
    my ($line) = @_;
    return (1) if $line =~ m/^\s*\[Mcast adjacency\]\s+\S+\s+0000\.0000\.0000\s/;
    return (0) unless $line =~ m/^\s*([0-9a-f:.]+)\s+\S+\s+($MAC_DOTTED)\s+([A-Z]+)\s+\S+(?:\s+\S+)?\s*$/i;
    my ($ip, $mac, $state) = ($1, $2, $3);
    return (1, (uc $state eq 'INCMP' ? undef : { ip => lc $ip, mac => mac_as_ieee($mac) }));
}

1;
