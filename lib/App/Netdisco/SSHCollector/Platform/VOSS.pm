package App::Netdisco::SSHCollector::Platform::VOSS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::VOSS

=head1 DESCRIPTION

Collect ARP entries from Extreme VSP devices running the VOSS operating system.

With C<store_vrfs> off, SNMP arpnip reads only the GlobalRouter VRF, so this
module is the way to collect ARP entries from the other VRFs. With it on, SNMP
reads each VRF too, and this module's C<arpnip_by_vrf> stores each entry under
its VRF and reads each VRF's IPv6 neighbors as well. C<arpnip> reads IPv4 only.

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
use Socket ();
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh, $args)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device. C<$args>
is the C<device_auth> entry; its C<vrfs> limits the VRFs read.

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

=item B<arpnip_by_vrf($host, $ssh, $args)>

As C<arpnip>, used when C<store_vrfs> is on. Also reads C<show ip vrf> and
C<show ipv6 neighbor vrfids>, and names each entry's VRF from the C<IP Arp> or
C<Neighbor Information> block it appears in (GlobalRouter is C<''>). IPv6
addresses are returned compressed. Neighbor rows are read whatever their TYPE
and STATE, and link-local and router-own rows are kept.

Returns C<{ entries =E<gt> [ { ip, mac, vrf } ], vrf_read =E<gt> { VRF =E<gt> 0|1 },
vrf_list_complete =E<gt> 0|1, families =E<gt> [4, 6] }>, or undef when the session,
C<show ip vrf> or the ARP command fails. A block is read whole when its footer
counts exactly the rows parsed. A VRF is 1 only when its ARP block and its
neighbor block were read whole; a VRF the device says has no IPv6 instance
(MgmtRouter) counts its IPv6 as read whole and empty. When the IPv6 command is
refused or times out, or the ARP command timed out so it is never sent,
C<families> is C<[4]> and C<vrf_read> covers IPv4 only. A C<vrfs> setting other
than C<0-512> makes C<vrf_list_complete> 0, so the VRFs it leaves out keep their
stored entries.

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

    my ($listed, $list_ok, $vrf_by_id) = _read_vrf_list($hostlabel, $expect);
    # a timed-out VRF list fails the read, as an ARP command error does
    my ($arp, $arp_whole) = (defined $list_ok
      ? _read_blocks($hostlabel, $expect, 'ARP', "show ip arp vrfids $vrflist", \&_parse_arp_blocks) : ());
    unless ($arp) {
        _close_session($expect);
        return undef;
    }

    # after a timeout the pty still holds the unfinished reply, so nothing
    # more is sent; a refused or timed-out IPv6 read leaves IPv4 only
    my ($nd, $nd_whole) = ($arp->{timed_out} ? () : _read_blocks($hostlabel, $expect,
      'IPv6 neighbors', "show ipv6 neighbor vrfids $vrflist", \&_parse_neighbor_blocks));
    ($nd, $nd_whole) = () if $nd and $nd->{timed_out};
    _close_session($expect);

    # a configured subset never vouches for VRFs it did not ask for, and
    # after a timeout or a partial block nothing is vouched for
    my $complete = ($list_ok and $arp_whole and (!$nd or $nd_whole) and $vrflist eq '0-512');
    my $result = _vrf_result($listed, $vrf_by_id, $arp, $nd, $complete);
    debug sprintf '[%s] arpnip - families [%s], %d IPv6 neighbor entries, VRF list %s',
      $hostlabel, join(', ', @{ $result->{families} }), ($nd ? scalar @{ $nd->{entries} } : 0),
      ($complete ? 'complete' : 'incomplete');
    return $result;
}

# a VRF is read whole when its ARP block was and, with IPv6 read, its
# neighbor block was or the device said it has no IPv6 instance
sub _vrf_result {
    my ($listed, $vrf_by_id, $arp, $nd, $complete) = @_;

    my %no_ipv6 = map { (defined $vrf_by_id->{$_} ? ($vrf_by_id->{$_} => 1) : ()) }
      @{ $nd ? $nd->{no_instance} : [] };
    my %vrf_read = map { ($_ => 0) } @$listed;
    foreach my $vrf (keys %{ $arp->{read} }) {
        my $ipv6_whole = (!$nd or $no_ipv6{$vrf} or $nd->{read}->{$vrf});
        $vrf_read{$vrf} = ($arp->{read}->{$vrf} and $ipv6_whole) ? 1 : 0;
    }

    return {
        entries => [ @{ $arp->{entries} }, ($nd ? @{ $nd->{entries} } : ()) ],
        vrf_read => \%vrf_read,
        vrf_list_complete => ($complete ? 1 : 0),
        families => ($nd ? [4, 6] : [4]),
    };
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

# returns the VRF names listed (GlobalRouter as ''), whether the list is
# whole: 1 or 0, or undef on a timeout, after which Expect still holds the
# partial output and nothing later can be parsed as fresh, and the names by
# VRF id
sub _read_vrf_list {
    my ($hostlabel, $expect) = @_;

    $expect->send("show ip vrf\n");
    my ($pos, undef, undef, $before) = $expect->expect(30, -re, $PROMPT);

    my (@names, %by_id, $shown, $total);
    foreach my $line (split m/\r?\n/, $before) {
        if ($line =~ m/^(\S+)\s+(\d+)\s+\d+\s+\d+\s+(?:TRUE|FALSE)\s/) {
            push @names, ($2 == 0 ? '' : $1);
            $by_id{$2} = $names[-1];
        }
        elsif ($line =~ m/^\s*(\d+) out of (\d+) Total Num of VRF Entries displayed/) {
            ($shown, $total) = ($1, $2);
        }
    }

    unless ($pos) {
        info "[$hostlabel] arpnip - show ip vrf timed out, no VRF read";
        return (\@names, undef, \%by_id);
    }
    my $whole = (defined $shown and $shown == $total and $shown == scalar @names) ? 1 : 0;
    return (\@names, $whole, \%by_id);
}

# returns ({ entries, read => { VRF => 0|1 }, no_instance => [ids], timed_out },
# whether every block was read whole), or nothing when the device answers an error
sub _read_blocks {
    my ($hostlabel, $expect, $what, $command, $parser) = @_;

    debug "[$hostlabel] arpnip - $command";
    $expect->send("$command\n");
    my ($pos, undef, undef, $before) = $expect->expect(60, -re, $PROMPT);

    if ($before =~ m/% Invalid input detected/ or $before =~ m/^\s*Error\s*:\s*([^\n]*)/m) {
        debug "error fetching $what [$hostlabel] : $command : " . ($1 // 'invalid command');
        return;
    }
    info "[$hostlabel] arpnip - $command timed out, no VRF read whole"
      unless $pos;

    my $blocks = $parser->($hostlabel, $before);
    # a block is whole only when its own footer counts exactly the rows parsed
    my %read = map {
        my $footer = $blocks->{footer}->{$_};
        ($_ => ($pos and defined $footer and $footer == $blocks->{rows}->{$_}) ? 1 : 0)
    } keys %{ $blocks->{rows} };
    my $whole = ($pos and not $blocks->{unrecognized} and not grep { !$_ } values %read) ? 1 : 0;

    return ({ entries => $blocks->{entries}, read => \%read,
              no_instance => ($blocks->{no_instance} || []), timed_out => ($pos ? 0 : 1) }, $whole);
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
        # the footer counts every row, so one without a MAC still counts
        next unless $line =~ m/^\s*($ipregex)\s+(\S+)/;
        my ($ip, $mac) = ($1, $2);
        $blocks{rows}->{$vrf}++;
        next unless $mac =~ m/^$macregex$/;
        debug "[$hostlabel] arpnip - vrf '$vrf' mac $mac ip $ip";
        push @{ $blocks{entries} }, { ip => $ip, mac => $mac, vrf => $vrf };
    }

    return \%blocks;
}

# Each neighbor is two lines: "ADDRESS/" with the columns, then the MAC
# indented. TYPE and STATE are not read: only static and local rows were ever
# captured, and learned ones carry other values.
sub _parse_neighbor_blocks {
    my ($hostlabel, $output) = @_;

    my $macregex = '(?:[[:xdigit:]]{2}:){5}[[:xdigit:]]{2}';

    my %blocks = (entries => [], rows => {}, footer => {}, unrecognized => 0, no_instance => []);
    my ($vrf, $address);
    foreach my $line (split m/\r?\n/, $output) {
        if ($line =~ m/^\s*Info: IPV6 Instance does not exist for VRF with id: ([\d,\-]+)/i) {
            push @{ $blocks{no_instance} }, _expand_vrf_ids($1);
            next;
        }
        # an unparsed header ends the previous block, so its rows are dropped
        if ($line =~ m/Neighbor Information - /) {
            $vrf = ($line =~ m/^\s*Neighbor Information - (?:VRF (\S+)|GlobalRouter)\s*$/) ? ($1 // '') : undef;
            undef $address;
            if (defined $vrf) { $blocks{rows}->{$vrf} //= 0 }
            else { $blocks{unrecognized} = 1; debug "[$hostlabel] arpnip - unparsed header: $line" }
            next;
        }
        next unless defined $vrf;
        if ($line =~ m/^\s*(\d+) out of \d+ Total Num of Neighbor Entries displayed/) {
            $blocks{footer}->{$vrf} = $1;
            next;
        }
        if ($line =~ m{^([[:xdigit:]]*:[[:xdigit:]:.]*)/\s}) {
            $address = $1;
            $blocks{rows}->{$vrf}++;
            next;
        }
        next unless defined $address and $line =~ m/^\s+($macregex)\s*$/;
        my $ip = _compress_ipv6($address);
        undef $address;
        next unless defined $ip;
        debug "[$hostlabel] arpnip - vrf '$vrf' mac $1 ip $ip";
        push @{ $blocks{entries} }, { ip => $ip, mac => $1, vrf => $vrf };
    }

    return \%blocks;
}

# "3-4,512" as (3, 4, 512)
sub _expand_vrf_ids {
    my $list = shift;
    return map { m/^(\d+)-(\d+)$/ ? ($1 .. $2) : (m/^\d+$/ ? $_ : ()) } split m/,/, $list;
}

# VOSS prints every group (2001:db8:1001:0:0:0:0:10); other drivers report
# the compressed form, so one address keeps one spelling
sub _compress_ipv6 {
    my $address = shift;
    my $packed = Socket::inet_pton(Socket::AF_INET6(), $address);
    return (defined $packed ? Socket::inet_ntop(Socket::AF_INET6(), $packed) : undef);
}

1;
