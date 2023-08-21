package App::Netdisco::SSHCollector::Platform::FortiOS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::FortiOS

=head1 DESCRIPTION

Collect ARP entries from Fortinet FortiOS Fortigate devices.

=cut

use strict;
use warnings;

use Dancer ':script';
use Moo;
use Expect;
use Regexp::Common qw(net);

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

If a post-login banner needs to be accepted, please set C<$banner> to true.

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.

=back

=cut

sub arpnip_context {
    my ($expect, $prompt, $timeout, $arpentries) = @_;

    # IPv4 ARP
    ##########

    $expect->send("get system arp\n");
    my ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my @data = split(/\R/, $before);

    # fortigate # get system arp
    # Address           Age(min)   Hardware Addr      Interface
    # 2.6.0.5     0          00:40:46:f9:63:0f PLAY-0400
    # 1.2.9.7      2          00:30:59:bc:f6:94 DEAD-3550

    foreach (@data) {
        if (/^($RE{net}{IPv4})\s*\d+\s*($RE{net}{MAC})\s*\S+$/) {
            debug "\tfound IPv4: $1 => MAC: $2";
            push(@$arpentries, { ip => $1, mac => $2 });
        }
    }

    # IPv6 ND
    ##########

    $expect->send("diagnose ipv6 neighbor-cache list\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    @data = split(/\R/, $before);

    # fortigate # diagnose ipv6 neighbor-cache list
    # ifindex=403 ifname=WORK-4016 fe80::abcd:1234:dead:f00d ab:cd:ef:01:23:45 state=00000004 use=42733 confirm=42733 update=41100 ref=3
    # ifindex=67 ifname=PLAY-4036 ff02::16 33:33:00:00:00:16 state=00000040 use=4765 confirm=10765 update=4765 ref=0
    # ifindex=28 ifname=root :: 00:00:00:00:00:00 state=00000040 use=589688110 confirm=589694110 update=589688110 ref=1
    # ifindex=48 ifname=FUN-4024 2001:42:1234:fe80:1234:1234:1234:1234 b0:c1:e2:f3:a4:b5 state=00000008 use=12 confirm=2 update=12 ref=2

    foreach (@data) {
        if (/^ifindex=\d+\s+ifname=\S+\s+($RE{net}{IPv6}{-sep => ':'}{-style => 'HeX'})\s+($RE{net}{MAC}).*$/) {
            debug "\tfound IPv6: $1 => MAC: $2";
            push(@$arpentries, { ip => $1, mac => $2 });
        }
    }
}

sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip()";

    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        warn "unable to run remote command [$hostlabel] " . $ssh->error;
        return ();
    }

    #$Expect::Debug = 1;
    #$Expect::Exp_Internal = 1;

    my $expect = Expect->init($pty);
    $expect->raw_pty(1);

    my ($pos, $error, $match, $before, $after);
    my $prompt = qr/ [\$#] +$/;
    my $timeout = 10;

    if ($args->{banner}) {
        my $banner = qr/^\(Press 'a' to accept\):/;
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $banner);

        $expect->send("a");
    }
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    # Check if we are in a VDOM context
    $expect->send("get system status\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my @data = split(/\R/, $before);
    my $multi_vdom = 0;
    foreach (@data) {
        if (/^Virtual domain configuration: multiple$/) {
            $multi_vdom = 1;
	    last;
        }
    }
    my $arpentries = [];
    if ($multi_vdom) {
        # Get list of all VDOM
        $expect->send("config global\n");
        $expect->expect($timeout, -re, $prompt);
        $expect->send("get system vdom-property\n");
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
        $expect->send("end\n");
        $expect->expect($timeout, -re, $prompt);
        @data = split(/\R/, $before);
        my $vdoms = [];
        foreach (@data) {
            push(@$vdoms, $1) if (/^==\s*\[\s*(\S+)\s*\]$/);
        }

        foreach (@$vdoms) {
            $expect->send("config vdom\n");
	    $expect->expect($timeout, -re, $prompt);
	    $expect->send("edit $_\n");
            $expect->expect($timeout, -re, $prompt);
            arpnip_context($expect, $prompt, $timeout, $arpentries);
            $expect->send("end\n");
            $expect->expect($timeout, -re, $prompt);
        }
    } else {
        arpnip_context($expect, $prompt, $timeout, $arpentries);
    }
    $expect->send("exit\n");
    $expect->soft_close();

    return @$arpentries;
}

1;
