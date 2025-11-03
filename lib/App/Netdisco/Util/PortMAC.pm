package App::Netdisco::Util::PortMAC;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ get_port_macs /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::PortMAC

=head1 DESCRIPTION

Helper subroutine to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 get_port_macs

Returns a Hash reference of C<< { MAC => IP } >> for all interface MAC
addresses supplied as array reference

=cut

sub get_port_macs {
    my ($fw_mac_list) = $_[0];
    my $port_macs = {};
    return {} unless ref [] eq ref $fw_mac_list and @{$fw_mac_list} >= 1;
    $fw_mac_list = [ grep {defined and length} @$fw_mac_list ];

    my $bindarray = [ { sqlt_datatype => "array" }, $fw_mac_list ];

    my $macs
        = schema(vars->{'tenant'})->resultset('Virtual::PortMacs')->search({},
        { bind => [$bindarray, $bindarray], select => [ 'mac', 'ip' ], group_by => [ 'mac', 'ip' ] } );
    my $cursor = $macs->cursor;
    while ( my @vals = $cursor->next ) {
        $port_macs->{ $vals[0] } = $vals[1];
    }

    return $port_macs;
}

1;
