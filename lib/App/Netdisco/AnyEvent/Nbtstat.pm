package App::Netdisco::AnyEvent::Nbtstat;

use strict;
use warnings;

use Socket qw(AF_INET SOCK_DGRAM inet_aton sockaddr_in);
use List::Util ();
use Carp       ();

use AnyEvent::Loop;
use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util ();

sub new {
    my ( $class, %args ) = @_;

    my $interval = $args{interval};
    # This default should generate ~ 50 requests per second
    $interval = 0.2 unless defined $interval;

    my $timeout = $args{timeout};

    # Timeout should be 250ms according to RFC1002, but we're going to double
    $timeout = 0.5 unless defined $timeout;

    my $self = bless { interval => $interval, timeout => $timeout, %args },
        $class;

    Scalar::Util::weaken( my $wself = $self );

    socket my $fh4, AF_INET, Socket::SOCK_DGRAM(), 0
        or Carp::croak "Unable to create socket : $!";

    AnyEvent::Util::fh_nonblocking $fh4, 1;
    $self->{fh4} = $fh4;
    $self->{rw4} = AE::io $fh4, 0, sub {
        if ( my $peer = recv $fh4, my $resp, 2048, 0 ) {
            $wself->_on_read( $resp, $peer );
        }
    };

    # Nbtstat tasks
    $self->{_tasks} = {};

    return $self;
}

sub interval { @_ > 1 ? $_[0]->{interval} = $_[1] : $_[0]->{interval} }

sub timeout { @_ > 1 ? $_[0]->{timeout} = $_[1] : $_[0]->{timeout} }

sub nbtstat {
    my ( $self, $host, $cb ) = @_;

    my $ip   = inet_aton($host);
    my $port = 137;

    my $request = {
        host        => $host,
        results     => {},
        cb          => $cb,
        destination => scalar sockaddr_in( $port, $ip ),
    };

    $self->{_tasks}{ $request->{destination} } = $request;

    my $delay = $self->interval * scalar keys %{ $self->{_tasks} || {} };

    # There's probably a better way to throttle the sends
    # but this will work for now since we currently don't support retries
    my $w; $w = AE::timer $delay, 0, sub {
        undef $w;
        $self->_send_request($request);
    };

    return $self;
}

sub _on_read {
    my ( $self, $resp, $peer ) = @_;

    ($resp) = $resp =~ /^(.*)$/s
        if AnyEvent::TAINT && $self->{untaint};

    # Find our task
    my $request = $self->{_tasks}{$peer};

    return unless $request;

    $self->_store_result( $request, 'OK', $resp );

    return;
}

sub _store_result {
    my ( $self, $request, $status, $resp ) = @_;

    my $results = $request->{results};

    my @rr          = ();
    my $mac_address = "";

    if ( $status eq 'OK' && length($resp) > 56 ) {
        my $num_names = unpack( "C", substr( $resp, 56 ) );
        my $name_data = substr( $resp, 57 );

        for ( my $i = 0; $i < $num_names; $i++ ) {
            my $rr_data = substr( $name_data, 18 * $i, 18 );
            push @rr, _decode_rr($rr_data);
        }

        $mac_address = join "-",
            map { sprintf "%02X", $_ }
            unpack( "C*", substr( $name_data, 18 * $num_names, 6 ) );
        $results = {
            'status'      => 'OK',
            'names'       => \@rr,
            'mac_address' => $mac_address
        };
    }
    elsif ( $status eq 'OK' ) {
        $results = { 'status' => 'SHORT' };
    }
    else {
        $results = { 'status' => $status };
    }

    # Clear request specific data
    delete $request->{timer};

    # Cleanup
    delete $self->{_tasks}{ $request->{destination} };

    # Done
    $request->{cb}->($results);

    undef $request;

    return;
}

sub _send_request {
    my ( $self, $request ) = @_;

    my $msg = "";
    # We use process id as identifier field, since don't have a need to
    # unique responses beyond host / port queried 
    $msg .= pack( "n*", $$, 0, 1, 0, 0, 0 );
    $msg .= _encode_name( "*", "\x00", 0 );
    $msg .= pack( "n*", 0x21, 0x0001 );

    $request->{start} = time;

    $request->{timer} = AE::timer $self->timeout, 0, sub {
        $self->_store_result( $request, 'TIMEOUT' );
    };

    my $fh = $self->{fh4};

    send $fh, $msg, 0, $request->{destination}
        or $self->_store_result( $request, 'ERROR' );

    return;
}

sub _encode_name {
    my $name   = uc(shift);
    my $pad    = shift || "\x20";
    my $suffix = shift || 0x00;

    $name .= $pad x ( 16 - length($name) );
    substr( $name, 15, 1, chr( $suffix & 0xFF ) );

    my $encoded_name = "";
    for my $c ( unpack( "C16", $name ) ) {
        $encoded_name .= chr( ord('A') + ( ( $c & 0xF0 ) >> 4 ) );
        $encoded_name .= chr( ord('A') + ( $c & 0xF ) );
    }

    # Note that the _encode_name function doesn't add any scope,
    # nor does it calculate the length (32), it just prefixes it
    return "\x20" . $encoded_name . "\x00";
}

sub _decode_rr {
    my $rr_data = shift;

    my @nodetypes = qw/B-node P-node M-node H-node/;
    my ( $name, $suffix, $flags ) = unpack( "a15Cn", $rr_data );
    $name =~ tr/\x00-\x19/\./;    # replace ctrl chars with "."
    $name =~ s/\s+//g;

    my $rr = {};
    $rr->{'name'}   = $name;
    $rr->{'suffix'} = $suffix;
    $rr->{'G'}      = ( $flags & 2**15 ) ? "GROUP" : "UNIQUE";
    $rr->{'ONT'}    = $nodetypes[ ( $flags >> 13 ) & 3 ];
    $rr->{'DRG'}    = ( $flags & 2**12 ) ? "Deregistering" : "Registered";
    $rr->{'CNF'}    = ( $flags & 2**11 ) ? "Conflict" : "";
    $rr->{'ACT'}    = ( $flags & 2**10 ) ? "Active" : "Inactive";
    $rr->{'PRM'}    = ( $flags & 2**9 ) ? "Permanent" : "";

    return $rr;
}

1;
__END__

=head1 NAME

App::Netdisco::AnyEvent::Nbtstat - Request NetBIOS node status with AnyEvent

=head1 SYNOPSIS

    use App::Netdisco::AnyEvent::Nbtstat;;

    my $request = App::Netdisco::AnyEvent::Nbtstat->new();

    my $cv = AE::cv;

    $request->nbtstat(
        '127.0.0.1',
        sub {
            my $result = shift;
            print "MAC: ", $result->{'mac_address'} || '', " ";
            print "Status: ", $result->{'status'}, "\n";
            printf '%3s %-18s %4s %-18s', '', 'Name', '', 'Type'
                if ( $result->{'status'} eq 'OK' );
            print "\n";
            for my $rr ( @{ $result->{'names'} } ) {
                printf '%3s %-18s <%02s> %-18s', '', $rr->{'name'},
                    $rr->{'suffix'},
                    $rr->{'G'};
                print "\n";
            }
            $cv->send;
        }
    );

    $cv->recv;

=head1 DESCRIPTION

L<App::Netdisco::AnyEvent::Nbtstat> is an asynchronous AnyEvent NetBIOS node
status requester.

=head1 ATTRIBUTES

L<App::Netdisco::AnyEvent::Nbtstat> implements the following attributes.

=head2 C<interval>

    my $interval = $request->interval;
    $request->interval(1);

Interval between requests, defaults to 0.02 seconds.

=head2 C<timeout>

    my $timeout = $request->timeout;
    $request->timeout(2);

Maximum request response time, defaults to 0.5 seconds.

=head1 METHODS

L<App::Netdisco::AnyEvent::Nbtstat> implements the following methods.

=head2 C<nbtstat>

    $request->nbtstat($ip, sub {
        my $result = shift;
    });

Perform a NetBIOS node status request of $ip.

=head1 SEE ALSO

L<AnyEvent>

=cut
