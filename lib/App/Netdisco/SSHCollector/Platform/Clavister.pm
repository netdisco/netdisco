package App::Netdisco::SSHCollector::Platform::Clavister;

# vim: set expandtab tabstop=8 softtabstop=4 shiftwidth=4:

=head1 NAME
App::Netdisco::SSHCollector::Platform::Clavister
=head1 DESCRIPTION
Collect ARP entries from Clavister firewalls.
These devices does not expose mac table through snmp.
=cut

use strict;
use warnings;
use Data::Dumper;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless ($self, $class);
    return $self;
}

=head1 PUBLIC METHODS
=over 4
=item B<arpnip($host, $ssh)>
Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.
Returns an array of hashrefs in the format { mac => MACADDR, ip => IPADDR }.
=cut
sub arpnip {

    my ($self, $hostlabel, $ssh, @args) = @_;

    print "$hostlabel $$ arpnip()\n";

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
