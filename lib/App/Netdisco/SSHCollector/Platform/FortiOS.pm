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

our $prompt = qr/ [\$#] +$/;
our $more_pattern = qr/--More--/;
our $timeout = 10;

sub get_paginated_output {
    my ($command, $expect) = @_;
    my $more_flag = 0;
    my @lines = undef;
    my @alllines = undef;
    $expect->send($command."\n");
    while (1) {
        my ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt, -re, $more_pattern);
        if ($match) {
            if ($match =~ $more_pattern) {
                $more_flag = 1;
                @lines = split(/\R/, $before);
                push(@alllines, grep {$_ =~ /\S/} @lines);
                debug("skipping through --More-- pagination");
                $expect->send(" ");
            } elsif ($match =~ $prompt) {
                $more_flag = 0;
                @lines = split(/\R/, $before);
                push(@alllines, grep {$_ =~ /\S/} @lines);
                foreach my $line (@alllines) {
                    debug("output collected: $line") if $line;
                }
                last;
            }
        }
    }

    return @alllines;
}

sub arpnip_context {
    my ($expect, $prompt, $timeout, $arpentries) = @_;

    # IPv4 ARP
    ##########

    my @data = get_paginated_output("get system arp", $expect);

    # fortigate # get system arp
    # Address           Age(min)   Hardware Addr      Interface
    # 2.6.0.5     0          00:40:46:f9:63:0f PLAY-0400
    # 1.2.9.7      2          00:30:59:bc:f6:94 DEAD-3550

    foreach (@data) {
        if ($_ && /^($RE{net}{IPv4})\s*\d+\s*($RE{net}{MAC})\s*\S+$/) {
            debug "\tfound IPv4: $1 => MAC: $2";
            push(@$arpentries, { ip => $1, mac => $2 });
        }
    }

    # IPv6 ND
    ##########

    @data = get_paginated_output("diagnose ipv6 neighbor-cache list", $expect);

    # fortigate # diagnose ipv6 neighbor-cache list
    # ifindex=403 ifname=WORK-4016 fe80::abcd:1234:dead:f00d ab:cd:ef:01:23:45 state=00000004 use=42733 confirm=42733 update=41100 ref=3
    # ifindex=67 ifname=PLAY-4036 ff02::16 33:33:00:00:00:16 state=00000040 use=4765 confirm=10765 update=4765 ref=0
    # ifindex=28 ifname=root :: 00:00:00:00:00:00 state=00000040 use=589688110 confirm=589694110 update=589688110 ref=1
    # ifindex=48 ifname=FUN-4024 2001:42:1234:fe80:1234:1234:1234:1234 b0:c1:e2:f3:a4:b5 state=00000008 use=12 confirm=2 update=12 ref=2

    # might fail with: Unknown action 0 - this is a permission issue of the logged in user

    foreach (@data) {
        if ($_ && /^ifindex=\d+\s+ifname=\S+\s+($RE{net}{IPv6}{-sep => ':'}{-style => 'HeX'})\s+($RE{net}{MAC}).*$/) {
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

    $Expect::Debug = 0;
    $Expect::Exp_Internal = 0;

    my $expect = Expect->init($pty);
    $expect->raw_pty(1);

    my ($pos, $error, $match, $before, $after);

    if ($args->{banner}) {
        my $banner = qr/^\(Press 'a' to accept\):/;
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $banner);

        $expect->send("a");
    }
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my @data = get_paginated_output("get system status", $expect);
    my $multi_vdom = 0;
    foreach (@data) {
        if ($_ && /^Virtual domain configuration: multiple$/) {
            $multi_vdom = 1;
        last;
        }
    }
    my $arpentries = [];
    if ($multi_vdom) {
        $expect->send("config global\n");
        $expect->expect($timeout, -re, $prompt);

        my @data = get_paginated_output("get system vdom-property", $expect);
        my $vdoms = [];
        foreach (@data) {
            push(@$vdoms, $1) if $_ && (/^==\s*\[\s*(\S+)\s*\]$/);
        }

        foreach (@$vdoms) {
            $expect->send("config vdom\n");
            $expect->expect($timeout, -re, $prompt);
            $expect->send("edit $_\n");
            debug ("switched to config vdom; edit $_");
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
