package App::Netdisco::Util::ExpandParams;
use base qw/CGI::Expand/;

use strict;
use warnings;

sub max_array {0}
sub separator {'.[]'}

sub split_name {
    my $class = shift;
    my $name  = shift;
    $name =~ /^ ([^\[\]\.]+) /xg;
    my @segs = $1;
    push @segs, ( $name =~ / \G (?: \[ ([^\[\]\.]+) \] ) /xg );
    return @segs;
}

sub join_name {
    my $class = shift;
    my ( $first, @segs ) = @_;
    return $first unless @segs;
    return "$first\[" . join( '][', @segs ) . "]";
}

1;

__END__

=head1 NAME

App::Netdisco::Util::ExpandParams

=head1 DESCRIPTION

CGI::Expand subclass with Rails like tokenization for parameters passed
during DataTables server-side processing.

=cut
