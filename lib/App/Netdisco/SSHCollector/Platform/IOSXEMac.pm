package App::Netdisco::SSHCollector::Platform::IOSXEMac;

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOSXEMac

=head1 DESCRIPTION

Collect MAC address-table entries (FDB) from Cisco IOS-XE via CLI
("show mac address-table"). Intended for platforms where
BRIDGE/Q-BRIDGE MIB does not expose the FDB (e.g. ISR/SD-WAN).

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use NetAddr::MAC qw/mac_as_ieee/;
use Moo;

# Expand short ifName prefixes to full names (kept in sync with IOS.pm)
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

=head2 macsuck($hostlabel, $ssh, $args)

Return a hashref like IOS.pm macsuck:
{ VLAN => { PORTNAME => { MAC_IEEE => 1 } } }

=cut
sub macsuck {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ macsuck() via IOSXEMac (Expect)";

    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        warn "unable to run remote command [$hostlabel] " . $ssh->error;
        return;
    }
    my $exp = Expect->init($pty);
    my ($pos, $err, $match, $before, $after);

    my $prompt  = qr/[>#]\s*$/;   # IOS-XE exec prompt
    my $timeout = 15;

    # reach prompt
    ($pos, $err, $match, $before, $after) = $exp->expect($timeout, -re => $prompt);

    # no paging
    $exp->send("terminal length 0\n");
    ($pos, $err, $match, $before, $after) = $exp->expect($timeout, -re => $prompt);

    # collect ALL entries (dynamic + static)
    $exp->send("show mac address-table\n");
    ($pos, $err, $match, $before, $after) = $exp->expect(30, -re => $prompt);

    my @lines = split /\r?\n/, ($before // '');

    # exit
    $exp->send("exit\n");
    $exp->hard_close();

    my $macentries = {};

    # Matches table rows:
    #   VLAN   MAC Address       Type      Ports
    #   10     0011.b908.1dfe    DYNAMIC   Gi0/1/3
    my $re_line = qr{
        ^\s*
        (\S+)                                      # VLAN_ID
        \s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}) # MAC dotted
        \s+(\S+)                                   # TYPE (DYNAMIC/STATIC/etc)
        \s+(\S+)                                   # PORT
        \s*$
    }ix;

    LINE: for my $line (@lines) {
        next if $line =~ /^\s*(Vlan|----|Mac Address Table|Total|$)/i;

        if ($line =~ $re_line) {
            my ($vlan, $mac_dotted, $type, $port_raw) = ($1, $2, uc($3), $4);

            # keep only numeric VLANs, skip CPU
            next LINE unless $vlan =~ /^\d+$/;
            next LINE if uc($port_raw) eq 'CPU';

            # expand interface name
            my ($pfx, $rest) = ($port_raw =~ /^([A-Za-z]+)(.*)$/);
            my $port = defined $pfx
              ? sprintf('%s%s', ($IF_NAME_MAP->{$pfx} || $pfx), ($rest || ''))
              : $port_raw;

            # convert MAC to colon IEEE format
            my $mac_ieee = mac_as_ieee($mac_dotted);

            ++$macentries->{$vlan}->{$port}->{$mac_ieee};
        }
    }

    debug "$hostlabel $$ parsed "
      . (0 + (map { scalar keys %{ $macentries->{$_} || {} } } keys %$macentries))
      . " port buckets (VLANs: " . join(',', sort keys %$macentries) . ")";

    return $macentries;
}

1;