package App::Netdisco::SSHCollector::Platform::Clavister;

=head1 NAME

App::Netdisco::SSHCollector::Platform::Clavister

=head1 DESCRIPTION

Collect ARP entries from Clavister firewalls.
These devices does not expose mac table through snmp.

=cut

use strict;
use warnings;

use Dancer ':script';
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.
Returns an array of hashrefs in the format { mac => MACADDR, ip => IPADDR }.

=back

=cut

sub arpnip {
    my ($self, $hostlabel, $ssh, @args) = @_;
    debug "$hostlabel $$ arpnip()";

    my @data = $ssh->capture("neighborcache");
    chomp @data;
    my @arpentries;

    foreach (@data){
        next if /^Contents of Active/;
        next if /^Idx/;
        next if /^---/;
        my @fields = split /\s+/, $_;
        my $mac = $fields[2];
        my $ip = $fields[3];
        push(@arpentries, {mac => $mac, ip => $ip});
    }
    return @arpentries;
}

1;
