package App::Netdisco::SSHCollector::Platform::IOSXE;

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOSXE

=head1 DESCRIPTION

CLI collectors for Cisco IOS-XE.

ARP:
IOS-XE does not always support "show ip arp vrf all". This module collects
the global ARP table and, when VRFs are present, enumerates VRFs from
"show vrf" and collects "show ip arp vrf <vrf>" for each. With C<store_vrfs>
on, C<arpnip_by_vrf> also reads IPv6 neighbors and keeps each entry's VRF.

MAC:
Collects forwarding entries from "show mac address-table" via an interactive
PTY (Expect) to avoid BRIDGE/Q-BRIDGE MIB gaps seen on some IOS-XE builds
and controller-managed deployments.

Both collectors normalise MAC formatting for Netdisco.

=head1 PUBLIC METHODS

=over 4

=item B<arpnip_by_vrf($host, $ssh, $args)>

As C<arpnip>, used when C<store_vrfs> is on. Reads C<show vrf>, then the global
C<show ip arp> and C<show ipv6 neighbors> and, for each listed VRF,
C<show ip arp vrf NAME> and, when the VRF lists C<ipv6> and the global
C<show ipv6 neighbors> answered, C<show ipv6 neighbors vrf NAME>. Each entry's
VRF is the one it was read from (the global table is C<''>). A VRF that does
not list C<ipv6> has no IPv6 table, so its IPv6 counts as read whole and empty.

Returns C<{ entries =E<gt> [ { ip, mac, vrf } ], vrf_read =E<gt> { VRF =E<gt> 0|1 },
vrf_list_complete =E<gt> 0|1, families =E<gt> [4, 6] }>, or undef when the
session fails or C<show vrf> times out. C<families> is C<[4]> when the global
C<show ipv6 neighbors> did not answer cleanly (IPv6 is unsupported or
unreached), and then C<vrf_read> covers IPv4 only; otherwise it is C<[4, 6]>.
A table is read whole when it returned to the prompt with no C<%> error and
every line was a header or an entry. A VRF is 1 only when its table for every
family in C<families> was read whole, so a VRF whose IPv6 table fails is 0
though its IPv4 entries are reported. A C<show vrf> is a whole list only when
it holds the header line and every other line is a VRF row or an interface-only
continuation (one name in the header's C<Interfaces> column); a reply without
the header (an error, a denial, nothing) makes C<vrf_list_complete> 0 and the
global tables are still read. A VRF named C<all> or with an unusual name is 0
and is never queried. Only a VRF named exactly C<default> is the global table;
C<Default> is a user VRF. After a timeout the rest of the session is not read,
and that VRF and every one not yet read are 0.

A subclass that overrides C<arpnip> must also override C<arpnip_by_vrf>, or
with C<store_vrfs> on this C<arpnip_by_vrf> is used instead of the override.

=back

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use NetAddr::MAC qw/mac_as_ieee/;
use Moo;

# Expand short interface name prefixes into canonical ifNames
my $IF_NAME_MAP = {
  Vl  => "Vlan",
  Lo  => "Loopback",
  Fa  => "FastEthernet",
  Gi  => "GigabitEthernet",
  Tw  => "TwoGigabitEthernet",
  Fi  => "FiveGigabitEthernet",
  Te  => "TenGigabitEthernet",
  Twe => "TwentyFiveGigE",
  Fo  => "FortyGigabitEthernet",
  Hu  => "HundredGigE",
  Po  => "Port-channel",
  Bl  => "Bluetooth",
  Wl  => "Wlan-GigabitEthernet",
};

sub _open_expect {
  my ($hostlabel, $ssh, $args, $purpose) = @_;

  my ($pty, $pid) = $ssh->open2pty;
  unless ($pty) {
    warn "unable to run remote command [$hostlabel] " . $ssh->error;
    return;
  }

  my $exp = Expect->init($pty);
  $exp->raw_pty(1);

  my $prompt  = qr/[>#]\s*$/;  # IOS-XE exec/enable prompt
  my $timeout = ($args && $args->{timeout}) ? $args->{timeout} : 30;

  my ($pos, $err, $match, $before, $after) = $exp->expect($timeout, -re => $prompt);
  unless (defined $pos) {
    info "$hostlabel $$ $purpose() unable to reach CLI prompt";
    $exp->hard_close();
    return;
  }

  # Disable paging so Expect sees complete command output
  $exp->send("terminal length 0\n");
  ($pos, $err, $match, $before, $after) = $exp->expect($timeout, -re => $prompt);

  debug "$hostlabel $$ $purpose() cli session ready";
  return ($exp, $prompt, $timeout);
}

# arpnip skips "default" in any case, as it always has; arpnip_by_vrf passes
# $case_sensitive because IOS-XE VRF names are
sub _parse_vrfs {
  my ($text, $case_sensitive) = @_;
  my @vrfs;

  # "show vrf" includes a Platform iVRF section on some builds; stop before that.
  for my $line (split /\r?\n/, ($text // '')) {
    last if $line =~ /^\s*Platform iVRF Name/i;
    next if $line =~ /^\s*$/;
    next if $line =~ /^\s*Name\s+Default RD/i;
    next if $line =~ /^\s*-+\s*$/;

    # IOS-XE prints VRF name in column 1 (indented)
    if ($line =~ /^\s+(\S+)\s+\S+\s+\S+/) {
      my $vrf = $1;
      next if ($case_sensitive ? $vrf eq 'default' : lc($vrf) eq 'default'); # global handled separately
      push @vrfs, $vrf;
    }
  }

  return @vrfs;
}

sub _parse_arp {
  my ($text, $seen) = @_;
  my @entries;
  my $added = 0;

  # Parse both "show ip arp" and "show ip arp vrf <name>" formats.
  for my $line (split /\r?\n/, ($text // '')) {
    next if !$line || $line =~ /^\s*$/;
    next if $line =~ /^\s*Protocol\s+Address\s+Age/i;

    my ($ip)  = $line =~ /(\d{1,3}(?:\.\d{1,3}){3})/;
    my ($mac) = $line =~ /([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})/i;
    next unless $ip && $mac;

    # Dedupe across global + VRFs
    my $key = lc("$ip|$mac");
    next if $seen->{$key}++;

    push @entries, { ip => $ip, mac => mac_as_ieee($mac) };
    ++$added;
  }

  return (\@entries, $added);
}

sub arpnip {
  my ($self, $hostlabel, $ssh, $args) = @_;
  debug "$hostlabel $$ arpnip()";

  my ($exp, $prompt, $timeout) = _open_expect($hostlabel, $ssh, $args, 'arpnip');
  return () unless $exp;

  my @arpentries;
  my %seen;

  # Stats are only for one end-of-run summary line
  my %stats = ( global => 0, vrf => {} );

  my ($pos, $err, $match, $before, $after);

  debug "$hostlabel $$ arpnip() collecting ARP from [global]";
  $exp->send("show ip arp\n");
  ($pos, $err, $match, $before, $after) = $exp->expect($timeout, -re => $prompt);

  my ($g_entries, $g_added) = _parse_arp($before, \%seen);
  push @arpentries, @$g_entries;
  $stats{global} += $g_added;

  # VRF enumeration; failures here should not block global ARP.
  $exp->send("show vrf\n");
  ($pos, $err, $match, $before, $after) = $exp->expect($timeout, -re => $prompt);

  my @vrfs = _parse_vrfs($before);
  debug "$hostlabel $$ arpnip() detected " . scalar(@vrfs) . " VRFs";

  for my $vrf (@vrfs) {
    debug "$hostlabel $$ arpnip() collecting ARP from [vrf:$vrf]";
    $exp->send("show ip arp vrf $vrf\n");
    ($pos, $err, $match, $before, $after) = $exp->expect($timeout, -re => $prompt);

    my ($v_entries, $v_added) = _parse_arp($before, \%seen);
    push @arpentries, @$v_entries;
    $stats{vrf}{$vrf} = ($stats{vrf}{$vrf} || 0) + $v_added;
  }

  $exp->send("exit\n");
  $exp->hard_close();

  my $total = scalar(@arpentries);
  my @parts = ("global=$stats{global}");
  for my $v (sort keys %{ $stats{vrf} }) {
    push @parts, "$v=$stats{vrf}{$v}";
  }
  debug "$hostlabel $$ arpnip() summary: total=$total (" . join(', ', @parts) . ")";

  return @arpentries;
}

# the prompt alone at the end of the output, so a row never ends a read
my $VRF_PROMPT = qr/^[^\s#>]+[>#]\s*\z/m;

my $IPV4_HEADER = qr/^\s*Protocol\s+Address\s+Age/i;
my $IPV6_HEADER = qr/^\s*IPv6 Address\s+Age\s+Link-layer/i;
my $MAC_DOTTED  = qr/[0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}/i;

sub arpnip_by_vrf {
  my ($self, $hostlabel, $ssh, $args) = @_;
  debug "$hostlabel $$ arpnip_by_vrf()";

  my ($exp, $timeout) = _open_vrf_session($hostlabel, $ssh, $args) or return undef;

  my $list = _run_command($exp, $timeout, 'show vrf');
  unless (defined $list) {
    info "$hostlabel $$ arpnip_by_vrf() show vrf timed out, so VRF collection by CLI was skipped";
    _close_vrf_session($exp);
    return undef;
  }
  my @vrfs = _parse_vrfs($list, 1);
  my $list_whole = _vrf_list_whole($list);
  info "$hostlabel $$ arpnip_by_vrf() show vrf was not a whole VRF list, so no VRF is vouched absent"
    unless $list_whole;
  my $protocols = _parse_vrf_protocols($list);

  my $state = { entries => [], seen => {}, whole => {}, unread => {}, timed_out => 0 };
  my $ipv6_answers = 0;
  my @plan = ([ '', 4, 'show ip arp' ], [ '', 6, 'show ipv6 neighbors' ]);
  while (my $step = shift @plan) {
    my ($vrf, $family, $command) = @$step;
    my $errored = _read_table($state, $exp, $timeout, $vrf, $family, $command);
    if ($family == 6 and $vrf eq '') {
      $ipv6_answers = !$errored;
      push @plan, map { _vrf_steps($_, $protocols, $ipv6_answers, $state) } @vrfs;
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
  } ('', @vrfs);

  return {
    entries => $state->{entries}, vrf_read => \%vrf_read,
    vrf_list_complete => (($state->{timed_out} or !$list_whole) ? 0 : 1), families => \@families,
  };
}

# The list is whole only when it holds the header and every other line is
# a VRF row or the interface-only line that continues the row above; a
# denied or unrecognized reply must not read as "no VRFs".
sub _vrf_list_whole {
  my ($text) = @_;
  my ($header, $after_row, $interfaces_column) = (0, 0, undef);
  for my $line (split /\r?\n/, $text) {
    last if $line =~ /^\s*Platform iVRF Name/i;
    next if $line =~ /^\s*$/ or $line =~ /^\s*-+\s*$/;
    return 0 if $line =~ /^\s*%/;
    if ($line =~ /^\s*Name\s+Default RD/i) {
      ($header, $interfaces_column) = (1, index($line, 'Interfaces'));
      next;
    }
    if ($line =~ /^\s+\S+\s+\S+\s+\S+/) { $after_row = 1; next }
    # a wrapped VRF name sits in the name column; only the Interfaces column continues a row
    return 0 unless $after_row and $interfaces_column >= 0
      and $line =~ /^(\s+)([A-Za-z]\S*\d\S*)\s*$/ and length($1) >= $interfaces_column;
  }
  return $header;
}

# the commands for one VRF; a VRF that lists no ipv6 has no IPv6 table, so
# that family is whole and empty with no command sent. A name that is not
# plain is never sent, and "all" would answer for every VRF at once.
sub _vrf_steps {
  my ($vrf, $protocols, $ipv6_answers, $state) = @_;
  unless ($vrf =~ m/\A[A-Za-z0-9_.:-]+\z/ and lc $vrf ne 'all') {
    $state->{unread}->{$vrf} = 1;
    return ();
  }
  my @steps = ([ $vrf, 4, "show ip arp vrf $vrf" ]);
  if (!$ipv6_answers) { return @steps }
  if (($protocols->{$vrf} // 'ipv6') =~ m/ipv6/i) {
    push @steps, [ $vrf, 6, "show ipv6 neighbors vrf $vrf" ];
  }
  else { $state->{whole}->{$vrf}->{6} = 1 }
  return @steps;
}

# VRF name => its Protocols column, where the row has one; wrapped interface
# lines hold no name and protocols, so they never match
sub _parse_vrf_protocols {
  my ($text) = @_;
  my %protocols;
  for my $line (split /\r?\n/, ($text // '')) {
    last if $line =~ /^\s*Platform iVRF Name/i;
    next unless $line =~ m/^\s+(\S+)\s+.*?\s(ipv[46](?:,ipv[46])*)(?:\s|$)/i;
    $protocols{$1} = $2;
  }
  return \%protocols;
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
  my ($state, $exp, $timeout, $vrf, $family, $command) = @_;

  my $output = _run_command($exp, $timeout, $command);
  unless (defined $output) {
    $state->{timed_out} = 1;
    $state->{unread}->{$vrf} = 1;
    return 1;
  }

  my ($entries, $whole, $errored) = _parse_table($output, $family);
  foreach my $entry (@$entries) {
    my $key = lc join '|', $vrf, @$entry{qw/ip mac/};
    next if $state->{seen}->{$key}++;
    push @{ $state->{entries} }, { %$entry, vrf => $vrf };
  }
  $state->{whole}->{$vrf}->{$family} = $whole;
  return $errored;
}

# returns the entries, whether every line was a header or an entry, and
# whether a "%" error line was seen
sub _parse_table {
  my ($output, $family) = @_;
  my ($header, $row) = ($family == 4
    ? ($IPV4_HEADER, \&_parse_arp_row) : ($IPV6_HEADER, \&_parse_neighbor_row));
  my (@entries, $errored);
  my $whole = 1;

  foreach my $line (split /\r?\n/, $output) {
    next if $line =~ m/^\s*$/ or $line =~ $header;
    if ($line =~ m/^\s*%/) { $errored = 1; $whole = 0; next }
    my ($recognized, $entry) = $row->($line);
    $whole = 0 unless $recognized;
    push @entries, $entry if $entry;
  }

  return (\@entries, $whole, $errored);
}

# returns whether the line is a row, and its entry unless the row is incomplete
sub _parse_arp_row {
  my ($line) = @_;
  return (0) unless $line =~ m/^\s*Internet\s+(\d{1,3}(?:\.\d{1,3}){3})\s+\S+\s+(?:($MAC_DOTTED)|Incomplete)\s/;
  return (1, ($2 ? { ip => $1, mac => mac_as_ieee($2) } : undef));
}

# IOS-XE prints IPv6 addresses in uppercase; an INCMP row has no usable MAC
sub _parse_neighbor_row {
  my ($line) = @_;
  return (0) unless $line =~ m/^\s*([0-9a-f:.]+)\s+(?:\d+|-)\s+(?:($MAC_DOTTED)|\S+)\s+([A-Z]+)\s+\S+\s*$/i;
  my ($ip, $mac, $state) = ($1, $2, $3);
  return (1, { ip => lc $ip, mac => mac_as_ieee($mac) }) if $mac;
  return (uc($state) eq 'INCMP' ? 1 : 0);
}

sub macsuck {
  my ($self, $hostlabel, $ssh, $args) = @_;
  debug "$hostlabel $$ macsuck()";

  my ($exp, $prompt, $timeout) = _open_expect($hostlabel, $ssh, $args, 'macsuck');
  return unless $exp;

  my ($pos, $err, $match, $before, $after);

  $exp->send("show mac address-table\n");
  ($pos, $err, $match, $before, $after) = $exp->expect($timeout, -re => $prompt);

  my @lines = split /\r?\n/, ($before // '');
  $exp->send("exit\n");
  $exp->hard_close();

  my $macentries = {};

  # Tolerant line match: grab VLAN + MAC + final port token
  # Handles variants with extra columns (age/secure/ntfy/etc).
  my $re_line = qr{
    ^\s*
    (\S+)                                      # VLAN (or All)
    \s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}) # MAC dotted
    \s+.*?                                     # anything (Type / Age / flags)
    \s+(\S+)                                   # Port (last column token)
    \s*$
  }ix;

  LINE: for my $line (@lines) {
    next if $line =~ /^\s*(Vlan|----|Mac Address Table|Total|$)/i;

    if ($line =~ $re_line) {
      my ($vlan_raw, $mac_dotted, $port_raw) = ($1, $2, $3);

      my $vlan = 0;
      if ($vlan_raw =~ /^\d+$/)         { $vlan = $vlan_raw; }
      elsif (lc($vlan_raw) eq 'all')    { $vlan = 0; }
      else                              { next LINE; }

      next LINE if uc($port_raw) eq 'CPU';

      # Expand short ifName prefix
      my ($pfx, $rest) = ($port_raw =~ /^([A-Za-z]+)(.*)$/);
      my $port = defined $pfx
        ? sprintf('%s%s', ($IF_NAME_MAP->{$pfx} || $pfx), ($rest || ''))
        : $port_raw;

      my $mac_ieee = mac_as_ieee($mac_dotted);
      ++$macentries->{$vlan}->{$port}->{$mac_ieee};
    }
  }

  debug "$hostlabel $$ macsuck() parsed VLANs: " . join(',', sort keys %$macentries)
    if keys %$macentries;

  return $macentries;
}

1;
