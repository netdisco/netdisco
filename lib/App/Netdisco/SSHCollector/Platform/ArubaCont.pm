package App::Netdisco::SSHCollector::Platform::ArubaCont;

=head1 NAME

App::Netdisco::SSHCollector::Platform::ArubaCont

=head1 DESCRIPTION

This module collects ARP entries from Aruba controllers.

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from the Aruba controller. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.
Returns a list of hashrefs in the format C<{ mac => MACADDR, ip => IPADDR }>.

=back

=cut

sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel arpnip() - Starting ARP collection for Aruba Controller";

    # Open pseudo-terminal
    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        debug "unable to run remote command [$hostlabel] " . $ssh->error;
        return ();
    }

    my $expect = Expect->init($pty);
    my $prompt = qr/#/;  # Adjust to match the Aruba controller prompt

    # Log into the controller and disable paging
    $expect->expect(10, -re, $prompt);
    $expect->send("no paging\n");
    $expect->expect(10, -re, $prompt);

    # Send 'show arp' command
    $expect->send("show arp\n");
    my ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    # Parse the ARP output
    my @data = split "\n", $before;
    my @arpentries;

    # Example regex matching for controller ARP output
    foreach my $line (@data) {
        if ($line =~ /(\d+\.\d+\.\d+\.\d+)\s+([\da-f:]+)\s+(vlan\d+)/) {
            push @arpentries, { ip => $1, mac => $2, port => $3 };
            debug "$hostlabel - Parsed ARP entry: IP=$1, MAC=$2, Port=$3";
        }
    }

    debug "$hostlabel - Parsed " . scalar(@arpentries) . " ARP entries";
    return @arpentries;
}

1;
