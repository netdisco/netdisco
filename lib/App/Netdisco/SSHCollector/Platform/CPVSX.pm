package App::Netdisco::SSHCollector::Platform::CPVSX;

=head1 NAME

App::Netdisco::SSHCollector::Platform::CPVSX

=head1 DESCRIPTION

Collect ARP entries from Check Point VSX

This collector uses "C<arp>" as the command for the arp utility on your
system. Clish "C<show arp>" does not work correctly in versions prior to R77.30.
Config example:

device_auth:
  - tag: sshcpvsx
    driver: cli
    platform: CPVSX
    only: '192.0.2.1'
    username: oliver
    password: letmein
    expert_password: letmein2


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

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.

=back

=cut

sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    my @arpentries = ();

    debug "$hostlabel $$ arpnip()";

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

    # TODO: check CP os/version via "cpstat os" and VSX status via "show vsx"
    # $expect->send("show vsx\n");
    # ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);
    # debug "$hostlabel $$ show vsx: $before";

    # Enumerate virtual systems
    # Virtual systems list
    # VS ID       VS NAME
    # 0           0
    # 1           BACKUP-VSX_xxxxxx_Context
    # ...

    $expect->send("show virtual-system all\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    my @vsxentries = ();
    my @lines = split(m/\n/, $before);

    my $linereg = qr/(\d+)\s+([A-Za-z0-9_-]+)/;
    foreach my $line (@lines) {
        if ($line =~ $linereg) {
            my ($vsid, $vsname) = ($1, $2);
            push @vsxentries, { vsid => $vsid,  vsname=> $vsname };
            debug "$hostlabel $$ $vsid, $vsname";
        }
    }

    # TODO:
    # Expert mode should be used only for pre-R77.30 versions
    # For R77.30 and later we can use:
    # set virtual-system $vsid
    # show arp dynamic all

    $expect->send("expert\n");

    $prompt = qr/Enter expert password:/;
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    $expect->send( $args->{expert_password} ."\n" );

    $prompt = qr/#/;
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    foreach (@vsxentries) {
        my $vsid = $_->{vsid};
        debug "$hostlabel $$ arpnip VSID: $vsid";

        $expect->send("vsenv $vsid\n");
        ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

        $expect->send("arp -n | tail -n +2\n");
        ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

        @lines = split(m/\n/, $before);

        # 192.168.1.1 ether 00:b6:aa:f5:bb:6e C eth1
        $linereg = qr/([0-9\.]+)\s+ether\s+([a-fA-F0-9:]+)/;

        foreach my $line (@lines) {
            if ($line =~ $linereg) {
                my ($ip, $mac) = ($1, $2);
                push @arpentries, { mac => $mac, ip => $ip };
                debug "$hostlabel $$ arpnip VSID: $vsid IP: $ip MAC: $mac";
            }
        }

    }

    $expect->send("exit\n");

    $prompt = qr/>/;
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    $expect->send("exit\n");

    $expect->soft_close();

    return @arpentries;
}

1;
