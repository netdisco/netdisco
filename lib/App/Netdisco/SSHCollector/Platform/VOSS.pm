package App::Netdisco::SSHCollector::Platform::VOSS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::VOSS

=head1 DESCRIPTION

Collect ARP entries from Extreme VSP devices running the VOSS operating system.

This is useful if running multiple VRFs as the built-in SNMP ARP collection will only fetch from the default GlobalRouter VRF.

By default this module gets ARP entries from all VRFs (0-512). To specify only certain VRFs in the config:

  device_auth:
    - tag: sshvsp
      driver: cli
      platform: VOSS
      only:
        - 10.1.1.1
        - 192.168.0.1
     username: oliver
     password: letmein
     vrfs: 1,5,100

The VRFs can be specified in any format that the "show ip arp vrfids" command will take. For example:

  1,2,3,4,5,10
  1-5,10
  1-100
  99

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

=item B<arpnip_by_vrf($host, $ssh, $args)>

As C<arpnip>, used when C<store_vrfs> is on. Also reads C<show ip vrf>, and
names each entry's VRF from the C<IP Arp> block it appears in (GlobalRouter is
C<''>).

Returns C<{ entries =E<gt> [ { ip, mac, vrf } ], vrf_read =E<gt> { VRF =E<gt> 0|1 },
vrf_list_complete =E<gt> 0|1, families =E<gt> [4] }>, or undef when the session,
C<show ip vrf> or the ARP command fails. Only IPv4 ARP is read, so
C<families> is C<[4]>: a VRF counts as read whole only when another source in
the same job read its IPv6 neighbors whole, so with this collector alone no
VRF's entries retire.

A subclass that overrides C<arpnip> must also override C<arpnip_by_vrf>, or
with C<store_vrfs> on this C<arpnip_by_vrf> is used instead of the override.

=back

=cut

sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip()";

    # default to entire range of VRFs
    my $vrflist = "0-512";
    # if specified in config, only get ARP from certain VRFs
    if ($args->{vrfs}) {
        if ($args->{vrfs} =~ m/^[0-9,\-]+$/) {
            $vrflist = $args->{vrfs};
        }
    }

    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        debug "unable to run remote command [$hostlabel] " . $ssh->error;
        return ();
    }
    my $expect = Expect->init($pty);

    my ($pos, $error, $match, $before, $after);
    my $prompt;

    $prompt = qr/>/;
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);
    
    $expect->send("terminal more disable\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    if ($before =~ m/% Invalid input detected/) {
        debug "invalid command [$hostlabel]";
        return ();
    }

    $expect->send("show ip arp vrfids $vrflist\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(60, -re, $prompt);
    my @lines = split(m/\n/, $before);

    if ($before =~ m/% Invalid input detected/) {
        debug "invalid command [$hostlabel]";
        return ();
    }

    if ($before =~ m/Error : ([^\n]+)/) {
        my $errormsg = $1;
        if ($errormsg =~ m/Invalid VRF ID/ || $errormsg =~ m/vrfId should be/) {
            debug "incorrect VRF specified [$hostlabel] : $vrflist : $errormsg";
            return ();
        }
        else {
            debug "general error fetching ARP [$hostlabel] : $errormsg";
            return ();
        }
    }

    my @arpentries;

    my $ipregex = '(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)';
    my $macregex = '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}';

    # IP Address    MAC Address     VLAN    Port    Type    TTL Tunnel
    # 172.16.20.15  0024.b269.867d  100     1/1     DYNAMIC 999 device-name
    foreach my $line (@lines) {
        next unless $line =~ m/^\s*$ipregex\s+$macregex/;
        my @fields = split m/\s+/, $line;

        debug "[$hostlabel] arpnip - mac $fields[1] ip $fields[0]";
        push @arpentries, { mac => $fields[1], ip => $fields[0] };
    }

    $expect->send("exit\n");
    $expect->soft_close();

    return @arpentries;
}

# the prompt as the captures show it (edge1:1>), alone at the end of the
# output: a > inside a row (a remote system name in TUNNEL) must not end a read
my $PROMPT = qr/^\S+:\d+[>#]\s*\z/m;

sub arpnip_by_vrf {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip_by_vrf()";

    my $vrflist = "0-512";
    if ($args->{vrfs} and $args->{vrfs} =~ m/^[0-9,\-]+$/) {
        $vrflist = $args->{vrfs};
    }

    my $expect = _open_session($hostlabel, $ssh) or return undef;
    my %result = (entries => [], vrf_read => {}, vrf_list_complete => 0, families => [4]);

    my ($listed, $list_ok) = _read_vrf_list($hostlabel, $expect);
    # a timed-out VRF list fails the read, as an ARP command error does
    my ($blocks, $arp_whole) = (defined $list_ok
      ? _read_arp_by_vrf($hostlabel, $expect, $vrflist) : ());
    unless ($blocks) {
        _close_session($expect);
        return undef;
    }

    $result{vrf_read}->{$_} = 0 for @$listed;
    @{ $result{vrf_read} }{ keys %{ $blocks->{read} } } = values %{ $blocks->{read} };
    $result{entries} = $blocks->{entries};
    # a configured subset never vouches for VRFs it did not ask for, and
    # after a timeout or a partial block nothing is vouched for
    $result{vrf_list_complete} = ($list_ok and $arp_whole and $vrflist eq '0-512') ? 1 : 0;

    _close_session($expect);
    return \%result;
}

# returns the Expect session after the pager is off, or undef
sub _open_session {
    my ($hostlabel, $ssh) = @_;

    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        debug "unable to run remote command [$hostlabel] " . $ssh->error;
        return undef;
    }
    my $expect = Expect->init($pty);

    my ($pos) = $expect->expect(10, -re, $PROMPT);
    unless ($pos) {
        info "[$hostlabel] arpnip - no prompt of the form <hostname>:<N>> seen,"
          . " so VRF collection by CLI was skipped for this device";
        _close_session($expect);
        return undef;
    }

    $expect->send("terminal more disable\n");
    my ($more_pos, undef, undef, $before) = $expect->expect(5, -re, $PROMPT);
    return _abandon($expect, "no prompt after terminal more disable [$hostlabel]")
      unless $more_pos;
    return _abandon($expect, "invalid command [$hostlabel]")
      if $before =~ m/% Invalid input detected/;

    return $expect;
}

sub _abandon {
    my ($expect, $message) = @_;
    debug $message;
    _close_session($expect);
    return undef;
}

sub _close_session {
    my $expect = shift;
    $expect->send("exit\n");
    $expect->soft_close();
}

# returns the VRF names listed (GlobalRouter as '') and whether the list is
# whole: 1 or 0, or undef on a timeout, after which Expect still holds the
# partial output and nothing later can be parsed as fresh
sub _read_vrf_list {
    my ($hostlabel, $expect) = @_;

    $expect->send("show ip vrf\n");
    my ($pos, undef, undef, $before) = $expect->expect(30, -re, $PROMPT);

    my (@names, $shown, $total);
    foreach my $line (split m/\r?\n/, $before) {
        if ($line =~ m/^(\S+)\s+(\d+)\s+\d+\s+\d+\s+(?:TRUE|FALSE)\s/) {
            push @names, ($2 == 0 ? '' : $1);
        }
        elsif ($line =~ m/^\s*(\d+) out of (\d+) Total Num of VRF Entries displayed/) {
            ($shown, $total) = ($1, $2);
        }
    }

    unless ($pos) {
        info "[$hostlabel] arpnip - show ip vrf timed out, no VRF read";
        return (\@names, undef);
    }
    my $whole = (defined $shown and $shown == $total and $shown == scalar @names) ? 1 : 0;
    return (\@names, $whole);
}

# returns ({ entries, read => { VRF => 0|1 } }, whether every block was read
# whole), or nothing when the device answers an error
sub _read_arp_by_vrf {
    my ($hostlabel, $expect, $vrflist) = @_;

    $expect->send("show ip arp vrfids $vrflist\n");
    my ($pos, undef, undef, $before) = $expect->expect(60, -re, $PROMPT);

    if ($before =~ m/% Invalid input detected/ or $before =~ m/^\s*Error\s*:\s*([^\n]*)/m) {
        debug "error fetching ARP [$hostlabel] : $vrflist : " . ($1 // 'invalid command');
        return;
    }
    info "[$hostlabel] arpnip - show ip arp vrfids $vrflist timed out, no VRF read whole"
      unless $pos;

    my $blocks = _parse_arp_blocks($hostlabel, $before);
    # a block is whole only when its own footer counts exactly the rows parsed
    my %read = map {
        my $footer = $blocks->{footer}->{$_};
        ($_ => ($pos and defined $footer and $footer == $blocks->{rows}->{$_}) ? 1 : 0)
    } keys %{ $blocks->{rows} };
    my $whole = ($pos and not $blocks->{unrecognized} and not grep { !$_ } values %read) ? 1 : 0;

    return ({ entries => $blocks->{entries}, read => \%read }, $whole);
}

sub _parse_arp_blocks {
    my ($hostlabel, $output) = @_;

    my $ipregex = '(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)';
    my $macregex = '(?:[[:xdigit:]]{2}:){5}[[:xdigit:]]{2}';

    my %blocks = (entries => [], rows => {}, footer => {}, unrecognized => 0);
    my $vrf;
    foreach my $line (split m/\r?\n/, $output) {
        # only "IP Arp - " heads ARP rows; an "IP Arp Extn - " header can name
        # another VRF (MgmtRouter's names GlobalRouter), so it never switches.
        # An unparsed header ends the previous block, so its rows are dropped.
        if ($line =~ m/IP Arp - /) {
            $vrf = ($line =~ m/^\s*IP Arp - (?:VRF (\S+)|GlobalRouter)\s*$/) ? ($1 // '') : undef;
            if (defined $vrf) { $blocks{rows}->{$vrf} //= 0 }
            else { $blocks{unrecognized} = 1; debug "[$hostlabel] arpnip - unparsed header: $line" }
            next;
        }
        next unless defined $vrf;
        if ($line =~ m/^\s*(\d+) out of \d+ ARP entries displayed/) {
            $blocks{footer}->{$vrf} = $1;
            next;
        }
        next unless $line =~ m/^\s*($ipregex)\s+($macregex)(?:\s|$)/;
        debug "[$hostlabel] arpnip - vrf '$vrf' mac $2 ip $1";
        push @{ $blocks{entries} }, { ip => $1, mac => $2, vrf => $vrf };
        $blocks{rows}->{$vrf}++;
    }

    return \%blocks;
}

1;
