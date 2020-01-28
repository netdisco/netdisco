package App::Netdisco::SSHCollector::Platform::IOSXR;

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOSXR

=head1 DESCRIPTION

Collect ARP entries from IOSXR routers using Expect

This is a reworked version of the IOSXR module, and it is suitable
for both 32- and 64-bit IOSXR.

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
        warn "unable to run remote command [$hostlabel] " . $ssh->error;
        return ();
    }
    my $expect = Expect->init($pty);

    my ($pos, $error, $match, $before, $after);
    my $prompt = qr/# +$/;
    my $timeout = 10;

    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    $expect->send("terminal length 0\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    $expect->send("show arp vrf all\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my @arpentries = ();
    my @data = split(m/\n/, $before);

    foreach (@data) {
        my ($ip, $age, $mac, $state, $t, $iface) = split(/\s+/);

        if ($ip =~ m/(\d{1,3}\.){3}\d{1,3}/
            && $mac =~ m/([0-9a-f]{4}\.){2}[0-9a-f]{4}/i) {
              push(@arpentries, { ip => $ip, mac => $mac });
        }
    }


    $expect->send("exit\n");
    $expect->hard_close();

    return @arpentries;
}

1;
