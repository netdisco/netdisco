package App::Netdisco::SSHCollector::Platform::ACE;

# vim: set expandtab tabstop=8 softtabstop=4 shiftwidth=4:

=head1 NAME

App::Netdisco::SSHCollector::Platform::ACE

=head1 DESCRIPTION

Collect ARP entries from Cisco ACE load balancers. ACEs have multiple
virtual contexts with individual ARP tables. Contexts are enumerated
with C<show context>, afterwards the commands C<changeto CONTEXTNAME> and
C<show arp> must be executed for every context.

The IOS shell does not permit to combine mulitple commands in a single
line, and Net::OpenSSH uses individual connections for individual commands,
so we need to use Expect to execute the changeto and show commands in
the same context.

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

sub arpnip{
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

    $expect->send("terminal length 0\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    $expect->send("show context | include Name\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    my @ctx;
    my @arpentries;

    for (split(/\n/, $before)){
        if (m/Name: (\S+)/){
            push(@ctx, $1);
            $expect->send("changeto $1\n");
            ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);
            $expect->send("show arp\n");
            ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);
            for (split(/\n/, $before)){
                my ($ip, $mac) = split(/\s+/);
                if ($ip =~ m/(\d{1,3}\.){3}\d{1,3}/ && $mac =~ m/[0-9a-f.]+/i) {
                    push(@arpentries, { ip => $ip, mac => $mac });
                }
            }

        }
    }

    $expect->send("exit\n");
    $expect->soft_close();

    return @arpentries;
}

1;
