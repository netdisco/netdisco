package App::Netdisco::Core::Nbtstat;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Node 'check_mac';
use NetAddr::IP::Lite ':lower';
use App::Netdisco::AnyEvent::Nbtstat;
use Encode;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ nbtstat_resolve_async store_nbt /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Core::Nbtstat

=head1 DESCRIPTION

Helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 nbtstat_resolve_async( $ips )

This method uses an asynchronous AnyEvent NetBIOS node status requester
C<App::Netdisco::AnyEvent::Nbtstat>.

Given a reference to an array of hashes will connects to the C<IPv4> of a
node and gets NetBIOS node status information.

Returns the supplied reference to an array of hashes with MAC address,
NetBIOS name, NetBIOS domain/workgroup, NetBIOS user, and NetBIOS server
service status for addresses which responded.

=cut

sub nbtstat_resolve_async {
    my $ips = shift;

    my $timeout  = setting('nbtstat_timeout')  || 1;
    my $interval = setting('nbtstat_interval') || 0.02;

    my $stater = App::Netdisco::AnyEvent::Nbtstat->new(
        timeout  => $timeout,
        interval => $interval
    );

    # Set up the condvar
    my $cv = AE::cv;
    $cv->begin( sub { shift->send } );

    foreach my $hash_ref (@$ips) {
        my $ip = $hash_ref->{'ip'};
        $cv->begin;
        $stater->nbtstat(
            $ip,
            sub {
                my $res = shift;
                _filter_nbname( $ip, $hash_ref, $res );
                $cv->end;
            }
        );
    }

    # Decrement the cv counter to cancel out the send declaration
    $cv->end;

    # Wait for the resolver to perform all resolutions
    $cv->recv;

    # Close sockets
    undef $stater;

    return $ips;
}

# filter nbt names / information
sub _filter_nbname {
    my $ip          = shift;
    my $hash_ref = shift;
    my $node_status = shift;

    my $server = 0;
    my $nbname = '';
    my $domain = '';
    my $nbuser = '';

    for my $rr ( @{$node_status->{'names'}} ) {
        my $suffix = defined $rr->{'suffix'} ? $rr->{'suffix'} : -1;
        my $G      = defined $rr->{'G'}      ? $rr->{'G'}      : '';
        my $name   = defined $rr->{'name'}   ? $rr->{'name'}   : '';

        if ( $suffix == 0 and $G eq "GROUP" ) {
            $domain = $name;
        }
        if ( $suffix == 3 and $G eq "UNIQUE" ) {
            $nbuser = $name;
        }
        if ( $suffix == 0 and $G eq "UNIQUE" ) {
            $nbname = $name unless $name =~ /^IS~/;
        }
        if ( $suffix == 32 and $G eq "UNIQUE" ) {
            $server = 1;
        }
    }

    unless ($nbname) {
      debug sprintf ' nbtstat no computer name found for %s', $ip;
        return;
    }

    my $mac = $node_status->{'mac_address'} || '';

    unless ( check_mac( $ip, $mac ) ) {

        # Just assume it's the last MAC we saw this IP at.
        my $node_ip = schema('netdisco')->resultset('NodeIp')
            ->single( { ip => $ip, -bool => 'active' } );

        if ( !defined $node_ip ) {
            debug sprintf ' no MAC for %s returned by nbtstat or in DB', $ip;
            return;
        }
        $mac = $node_ip->mac;
    }

        $hash_ref->{'ip'} = $ip;
        $hash_ref->{'mac'}    = $mac;
        $hash_ref->{'nbname'} = Encode::decode('UTF-8', $nbname);
        $hash_ref->{'domain'} = Encode::decode('UTF-8', $domain);
        $hash_ref->{'server'} = $server;
        $hash_ref->{'nbuser'} = Encode::decode('UTF-8', $nbuser);
        
    return;
}

=head2 store_nbt($nb_hash_ref, $now?)

Stores entries in C<node_nbt> table from the provided hash reference; MAC
C<mac>, IP C<ip>, Unique NetBIOS Node Name C<nbname>, NetBIOS Domain or
Workgroup C<domain>, whether the Server Service is running C<server>,
and the current NetBIOS user C<nbuser>.

Adds new entry or time stamps matching one.

Optionally a literal string can be passed in the second argument for the
C<time_last> timestamp, otherwise the current timestamp (C<now()>) is used.

=cut

sub store_nbt {
    my ( $hash_ref, $now ) = @_;
    $now ||= 'now()';

    schema('netdisco')->resultset('NodeNbt')->update_or_create(
        {   mac       => $hash_ref->{'mac'},
            ip        => $hash_ref->{'ip'},
            nbname    => $hash_ref->{'nbname'},
            domain    => $hash_ref->{'domain'},
            server    => $hash_ref->{'server'},
            nbuser    => $hash_ref->{'nbuser'},
            active    => \'true',
            time_last => \$now,
        },
        {   key => 'primary',
            for => 'update',
        }
    );

    return;
}

1;
