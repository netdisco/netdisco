package App::Netdisco::SSHCollector::Platform::IOSXE;

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOSXE

=head1 DESCRIPTION

CLI collectors for Cisco IOS-XE.

ARP:
IOS-XE does not always support "show ip arp vrf all". This module collects
the global ARP table and, when VRFs are present, enumerates VRFs from
"show vrf" and collects "show ip arp vrf <vrf>" for each.

MAC:
Collects forwarding entries from "show mac address-table" via an interactive
PTY (Expect) to avoid BRIDGE/Q-BRIDGE MIB gaps seen on some IOS-XE builds
and controller-managed deployments.

Both collectors normalise MAC formatting for Netdisco.

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

sub _parse_vrfs {
  my ($text) = @_;
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
      next if lc($vrf) eq 'default'; # global handled separately
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
