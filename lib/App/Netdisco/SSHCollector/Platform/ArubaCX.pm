package App::Netdisco::SSHCollector::Platform::ArubaCX;

=head1 NAME

App::Netdisco::SSHCollector::Platform::ArubaCX

=head1 DESCRIPTION

Collect ARP entries from ArubaCX devices

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

    $expect->send("show arp\n");
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

1;
