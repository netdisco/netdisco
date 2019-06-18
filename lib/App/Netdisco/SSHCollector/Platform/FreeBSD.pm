package App::Netdisco::SSHCollector::Platform::FreeBSD;

=head1 NAME

App::Netdisco::SSHCollector::Platform::FreeBSD

=head1 DESCRIPTION

Collect ARP entries from FreeBSD routers.

This collector uses "C<arp>" as the command for the arp utility on your
system.  If you wish to specify an absolute path, then add an C<arp_command>
item to your configuration:

 device_auth:
   - tag: sshfreebsd
     driver: cli
     platform: FreeBSD
     only: '192.0.2.1'
     username: oliver
     password: letmein
     arp_command: '/usr/sbin/arp'
    
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
    my $prompt = qr/\$/;

    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    my $command = ($args->{arp_command} || 'arp');
    $expect->send("$command -n -a\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    my @arpentries = ();
    my @lines = split(m/\n/, $before);

    # ? (192.0.2.1) at fe:ed:de:ad:be:ef on igb0_vlan2 expires in 658 seconds [vlan]
    my $linereg = qr/\s+\((\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\)\s+at\s+([a-fA-F0-9:]{17})\s+on/;

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
