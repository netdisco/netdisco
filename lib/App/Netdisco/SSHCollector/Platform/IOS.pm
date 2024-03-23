package App::Netdisco::SSHCollector::Platform::IOS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOS

=head1 DESCRIPTION

Collect ARP entries from Cisco IOS devices.

=cut

use strict;
use warnings;

use Dancer ':script';
use NetAddr::MAC qw/mac_as_ieee/;
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

=back

=cut

my $if_name_map = {
  Vl => "Vlan",
  Lo => "Loopback",
  Fa => "FastEthernet",
  Gi => "GigabitEthernet",
  Tw => "TwoGigabitEthernet",
  Fi => "FiveGigabitEthernet",
  Te => "TenGigabitEthernet",
  Twe => "TwentyFiveGigE",
  Fo => "FortyGigabitEthernet",
  Hu => "HundredGigE",
  Po => "Port-channel",
  Bl => "Bluetooth",
};

sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip()";
    my @data = $ssh->capture("show ip arp");

    chomp @data;
    my @arpentries;

    # Internet  172.16.20.15   13   0024.b269.867d  ARPA FastEthernet0/0.1
    foreach my $line (@data) {
        next unless $line =~ m/^Internet/;
        my @fields = split m/\s+/, $line;

        push @arpentries, { mac => $fields[3], ip => $fields[1] };
    }

    return @arpentries;
}

sub macsuck {
  my ($self, $hostlabel, $ssh, $args) = @_;
  
  debug "$hostlabel $$ macsuck()";
  my $cmds = <<EOF;
terminal length 0
show interfaces description
show mac address-table
EOF
  my @data = $ssh->capture({stdin_data => $cmds}); chomp @data;
  if ($ssh->error) {
    info "$hostlabel $$ error in SSH command " . $ssh->error;
    return;
  }

  my $interfaces = {};
  my $macentries = {};
  my $re_interface_line = qr/^([a-z]+)([0-9\/\.]+)\s+(up|down|admin down)\s+(up|down)/i;
  my $re_mac_line = qr/^\s*(All|[0-9]+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+\S+\s+([a-zA-Z]+)([0-9\/\.]+)/i;
  my $port;
  foreach (@data) {
    if ($_ && /$re_interface_line/) {
      $port = sprintf "%s%s", $if_name_map->{$1}, $2;
      $interfaces->{$port} = {
        up_admin => ($3 eq "admin down") ? "down" : "up",
        up => ($3 eq "down") ? "down" : "up",
      };
    } elsif ($_ && /$re_mac_line/) {
      $port = sprintf "%s%s", $if_name_map->{$3}, $4;
      ++$macentries->{$1}->{$port}->{mac_as_ieee($2)};
    }
  }

  return ($interfaces,$macentries);
}

1;
