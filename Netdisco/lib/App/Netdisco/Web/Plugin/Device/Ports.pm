package App::Netdisco::Web::Plugin::Device::Ports;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_device_tab(
    { tag => 'ports', label => 'Ports', provides_csv => 1 } );

# device ports with a description (er, name) matching
get '/ajax/content/device/ports' => require_login sub {
    my $q      = param('q');
    my $prefer = param('prefer');
    $prefer = ''
        unless defined $prefer and $prefer =~ m/^(?:port|name|vlan)$/;

    my $device
        = schema('netdisco')->resultset('Device')->search_for_device($q)
        or send_error( 'Bad device', 400 );
    my $rs = $device->ports_flattened;

    # refine by ports if requested
    my $f = param('f');
    if ($f) {
        if ( ( $prefer eq 'vlan' ) or not $prefer and $f =~ m/^\d+$/ ) {
            if ( param('invert') ) {
                $rs = $rs->search(
                    {   'me.vlan' => { '!=' => $f },
                        '-or'     => [
                            -not_bool => {
                                'me.vlan_membership' =>
                                    { '@>' => { -value => [$f] } }
                            },
                            'me.vlan_membership' => { '=' => undef },
                        ]
                    }
                );
            }
            else {
                $rs = $rs->search(
                    {   -or => {
                            'me.vlan' => $f,
                            'me.vlan_membership' =>
                                { '@>' => { -value => [$f] } },
                        },
                    }
                );
            }

            return unless $rs->count;
        }
        else {
            if ( param('partial') ) {

                # change wildcard chars to SQL
                $f =~ s/\*/%/g;
                $f =~ s/\?/_/g;

                # set wilcards at param boundaries
                if ( $f !~ m/[%_]/ ) {
                    $f =~ s/^\%*/%/;
                    $f =~ s/\%*$/%/;
                }

                # enable ILIKE op
                $f = { ( param('invert') ? '-not_ilike' : '-ilike' ) => $f };
            }
            elsif ( param('invert') ) {
                $f = { '!=' => $f };
            }

            if ( ( $prefer eq 'port' )
                or not $prefer and $rs->search( { 'me.port' => $f } )->count )
            {

                $rs = $rs->search(
                    {   -or => [
                            'me.port'     => $f,
                            'me.slave_of' => $f,
                        ],
                    }
                );
            }
            else {
                $rs = $rs->search( { 'me.name' => $f } );
                return unless $rs->count;
            }
        }
    }

    # filter for port status if asked
    my %port_state = map { $_ => 1 } (
          ref [] eq ref param('port_state') ? @{ param('port_state') }
        : param('port_state') ? param('port_state')
        : ()
    );

    # user deseleted all port states. that means no ports.
    return unless scalar keys %port_state;

    # if four keys, that's shorthand for everything.
    # so only add these filters if user deselected something.
    if (scalar keys %port_state != 4) {
        my @combi = ();

        if ( exists $port_state{free} ) {
            my $age_num  = ( param('age_num')  || 3 );
            my $age_unit = ( param('age_unit') || 'months' );
            my $interval = "$age_num $age_unit";

            push @combi, { -and => [
                { 'me.up_admin' => 'up', 'me.up' => { '!=' => 'up' } },
                \[ "age(now(), to_timestamp(extract(epoch from me.device_last_discover) "
                            . "- (me.device_uptime - me.lastchange)/100)) "
                            . "> ?::interval",
                        [ {} => $interval ] ],
            ]};
        }

        push @combi, { 'me.up' => 'up' }
            if exists $port_state{up};
        push @combi, { 'me.up_admin' => 'up', 'me.up' => { '!=' => 'up' } }
            if exists $port_state{down};
        push @combi, { 'me.up_admin' => { '!=' => 'up' } }
            if exists $port_state{shut};

        $rs = $rs->search( { -or => \@combi } );
    }

    # retrieve active/all connected nodes, if asked for
    $rs
        = $rs->search_rs( {},
        { prefetch => 'nodes', bind => [ $device->ip ] } )
        if param('c_nodes');

    my @results = $rs->hri->all;
    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/device/ports.tt',
            { results => to_json( \@results ), }, { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/device/ports_csv.tt', { results => \@results, },
            { layout => undef };
    }
};

1;
