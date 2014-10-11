package App::Netdisco::SSHCollector::Platform::PaloAlto;

# vim: set expandtab tabstop=8 softtabstop=4 shiftwidth=4:

=head1 NAME

App::Netdisco::SSHCollector::Platform::PaloAlto

=head1 DESCRIPTION

Collect ARP entries from PaloAlto devices.

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

sub arpnip{
    my ($self, $hostlabel, $ssh, @args) = @_;

    debug "$hostlabel $$ arpnip()";

    my ($pty, $pid) = $ssh->open2pty or die "unable to run remote command";
    my $expect = Expect->init($pty);
    my ($pos, $error, $match, $before, $after);
    my $prompt = qr/> \r?$/;

    ($pos, $error, $match, $before, $after) = $expect->expect(20, -re, $prompt);
    $expect->send("set cli pager off\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);
    $expect->send("show arp all\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    my @arpentries;
    for (split(/\r\n/, $before)){
        next unless $_ =~ m/(\d{1,3}\.){3}\d{1,3}/;
        my ($tmp, $ip, $mac) = split(/\s+/);
        if ($ip =~ m/(\d{1,3}\.){3}\d{1,3}/ && $mac =~ m/([0-9a-f]{2}:){5}[0-9a-f]{2}/i) {
             push(@arpentries, { ip => $ip, mac => $mac });
        }
    }
    $expect->send("exit\n");
    $expect->soft_close();

    return @arpentries;
}

1;
