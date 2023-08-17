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

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

If a post-login banner needs to be accepted, please set C<$banner> to true.

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.

=back

=cut

# Notes by FortiNoob @rc9000 :
# * This version with VDOM support was made without access to a device that does not use VDOMs. If you encounter issues, please revert to 
#    https://github.com/netdisco/netdisco/blob/5cc876e2298783b3e4afc5c2d173103c595abce7/lib/App/Netdisco/SSHCollector/Platform/FortiOS.pm
# * This requires permissions to enumerate vdoms and run diagnose commands. It should silently fail and continue if that's not the case,
#   but not much testing was done for that.
# * Tested only on FortiGate-6300F v6.4.12

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

    $expect->send("show\r");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my $config_output = $before;

    my %vdom_hash;
    while ($config_output =~ /config vdom\s+edit (\S+)?/g) {
        $vdom_hash{$1} = 1;
    }
    my @vdom_names = keys %vdom_hash;

    debug "$hostlabel $$ discovered vdom names: <@vdom_names>";

    my @arpentries;

    # try ipv4 global
    push @arpentries, @{$self->get_ipv4($hostlabel, $expect, $prompt, $timeout, undef)};
    # try ipv4 vdoms
    foreach my $vdom (@vdom_names) {
        push @arpentries, @{$self->get_ipv4($hostlabel, $expect, $prompt, $timeout, $vdom)};
    }

    # try ipv6 global
    push @arpentries, @{$self->get_ipv6($hostlabel, $expect, $prompt, $timeout, undef)};
    # try ipv6 vdoms
    foreach my $vdom (@vdom_names) {
        push @arpentries, @{$self->get_ipv6($hostlabel, $expect, $prompt, $timeout, $vdom)};
    }

    $expect->send("exit\n");
    $expect->soft_close();
    return @arpentries; 

}

sub get_ipv4 {
    my ($self, $hostlabel, $expect, $prompt, $timeout, $vdom) = @_;
    my ($pos, $error, $match, $before, $after);

    debug "$hostlabel $$ get ipv4 arp" . ($vdom ? " for vdom $vdom" : " (non-vdom)");

    if ($vdom){
        $expect->send("config vdom\n");
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
        $expect->send("edit $vdom\n");
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
    }

    $expect->send("get system arp\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my @arpentries;
    my @data = split(/\R/, $before);

    # sample:
    # fortigate # get system arp
    # Address      Age(min)   Hardware Addr      Interface
    # 2.6.0.5      0          00:40:46:f9:63:0f PLAY-0400
    # 1.2.9.7      2          00:30:59:bc:f6:94 DEAD-3550

    foreach (@data) {
        my ($ip, $age, $mac, $iface) = split(/\s+/);

        if ($ip && $ip =~ m/(\d{1,3}\.){3}\d{1,3}/
            && $mac =~ m/([0-9a-f]{2}\:){5}[0-9a-f]{2}/i) {
              push(@arpentries, { ip => $ip, mac => $mac });
        }
    }

    if ($vdom){
        $expect->send("end\n");
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
    }

    return \@arpentries;
}

sub get_ipv6 {

    my ($self, $hostlabel, $expect, $prompt, $timeout, $vdom) = @_;
    my ($pos, $error, $match, $before, $after);

    debug "$hostlabel $$ get ipv6 neighbor-cache" . ($vdom ? " for vdom $vdom" : " (non-vdom)");

    if ($vdom){
        $expect->send("config vdom\n");
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
        $expect->send("edit $vdom\n");
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
    }

    $expect->send("diagnose ipv6 neighbor-cache list\n");
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    my @arpentries;
    my @data = split(/\R/, $before);

    # sample:
    # fortigate # diagnose ipv6 neighbor-cache list
    # ifindex=403 ifname=WORK-4016 fe80::abcd:1234:dead:f00d ab:cd:ef:01:23:45 state=00000004 use=42733 confirm=42733 update=41100 ref=3
    # ifindex=67 ifname=PLAY-4036 ff02::16 33:33:00:00:00:16 state=00000040 use=4765 confirm=10765 update=4765 ref=0
    # ifindex=28 ifname=root :: 00:00:00:00:00:00 state=00000040 use=589688110 confirm=589694110 update=589688110 ref=1
    # ifindex=48 ifname=FUN-4024 2001:42:1234:fe80:1234:1234:1234:1234 b0:c1:e2:f3:a4:b5 state=00000008 use=12 confirm=2 update=12 ref=2

    foreach (@data) {
        my ($ifindex, $ifname, $ip, $mac, $state, $use, $confirm, $update, $ref) = split(/\s+/);

        if ($ip && $ip =~ m/[0-9a-f]{0,4}:([0-9a-f]{0,4}:){0,6}:[0-9a-f]{0,4}/
            && $mac =~ m/([0-9a-f]{2}\:){5}[0-9a-f]{2}/i) {
              push(@arpentries, { ip => $ip, mac => $mac });
        }
    }

    if ($vdom){
        $expect->send("end\n");
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
    }

    return \@arpentries;
}

1;
