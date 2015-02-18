package App::Netdisco::SSHCollector::Platform::ASA;


=head1 NAME

App::Netdisco::SSHCollector::Platform::ASA

=head1 DESCRIPTION

Collect ARP entries from Cisco ASA devices.

You will need the following configuration for the user to automatically enter
C<enable> status after login:

 aaa authorization exec LOCAL auto-enable

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

Returns an array of hashrefs in the format { mac => MACADDR, ip => IPADDR }.

=cut

sub arpnip {
    my ($self, $hostlabel, $ssh, @args) = @_;

    debug "$hostlabel $$ arpnip()";

    my ($pty, $pid) = $ssh->open2pty or die "unable to run remote command";
    my $expect = Expect->init($pty);

    my ($pos, $error, $match, $before, $after);
    my $prompt = qr/#/;

    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    $expect->send("terminal pager 2147483647\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    $expect->send("show arp\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(60, -re, $prompt);

    my @arpentries = ();
    my @lines = split(m/\n/, $before);

    # ifname 192.0.2.1 0011.2233.4455 123
    my $linereg = qr/[A-z0-9\-\.]+\s([A-z0-9\-\.]+)\s
                     ([0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4})/x;

    foreach my $line (@lines) {
        if ($line =~ $linereg) {
            my ($ip, $mac) = ($1, $2);
            push @arpentries, { mac => $mac, ip => $ip };
        }
    }

    $expect->send("exit\n");
    $expect->soft_close();

    return @arpentries;
}

1;
