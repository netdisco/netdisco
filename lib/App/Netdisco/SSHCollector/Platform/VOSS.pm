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

1;
