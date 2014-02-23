package App::Netdisco::Core::Nbtstat;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Node 'check_mac';
use NetAddr::IP::Lite ':lower';
use Time::HiRes 'gettimeofday';
use Net::NBName;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ do_nbtstat store_nbt /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Core::Nbtstat

=head1 DESCRIPTION

Helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 do_nbtstat( $node ) 

Connects to node and gets NetBIOS information. Then adds entries to
node_nbt table.

Returns whether a node is answering netbios calls or not.

=cut

sub do_nbtstat {
    my $host = shift;

    my $ip = NetAddr::IP::Lite->new($host) or return;

    unless ( $ip->version() == 4 ) {
        debug ' nbtstat only supports IPv4, invalid ip %s', $ip->addr;
        return;
    }

    my $nb = Net::NBName->new;

    my $ns = $nb->node_status( $ip->addr );

    # Check for NetBIOS Info
    return unless $ns;

    my $nbname = _filter_nbname( $ip->addr, $ns );

    if ($nbname) {
        store_nbt($nbname);
    }

    return 1;
}

# filter nbt names / information
sub _filter_nbname {
    my $ip          = shift;
    my $node_status = shift;

    my $server = 0;
    my $nbname = '';
    my $domain = '';
    my $nbuser = '';

    for my $rr ( $node_status->names ) {
        my $suffix = defined $rr->suffix ? $rr->suffix : -1;
        my $G      = defined $rr->G      ? $rr->G      : '';
        my $name   = defined $rr->name   ? $rr->name   : '';

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
        debug ' nbtstat no computer name found for %s', $ip;
        return;
    }

    my $mac = $node_status->mac_address || '';

    unless ( check_mac( $ip, $mac ) ) {

        # Just assume it's the last MAC we saw this IP at.
        my $node_ip = schema('netdisco')->resultset('NodeIp')
            ->single( { ip => $ip, -bool => 'active' } );

        if ( !defined $node_ip ) {
            debug ' no MAC for %s returned by nbtstat or in DB', $ip;
            return;
        }
        $mac = $node_ip->mac;
    }

    return {
        ip     => $ip,
        mac    => $mac,
        nbname => $nbname,
        domain => $domain,
        server => $server,
        nbuser => $nbuser
    };
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
