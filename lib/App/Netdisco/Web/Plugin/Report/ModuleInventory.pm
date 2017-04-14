package App::Netdisco::Web::Plugin::Report::ModuleInventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::ExpandParams 'expand_hash';

use App::Netdisco::Web::Plugin;
use List::MoreUtils ();

register_report(
    {   category     => 'Device',
        tag          => 'moduleinventory',
        label        => 'Module Inventory',
        provides_csv => 1,
    }
);

hook 'before' => sub {
    return
        unless (
        request->path eq uri_for('/report/moduleinventory')->path
        or index( request->path,
            uri_for('/ajax/content/report/moduleinventory')->path ) == 0
        );

    # view settings
    var('module_options' => [
            {   name    => 'fruonly',
                label   => 'FRU Only',
                default => 'on'
            },
            {   name    => 'matchall',
                label   => 'Match All Options',
                default => 'on'
            },
        ]
    );
};

hook 'before_template' => sub {
    my $tokens = shift;

    return
        unless (
        request->path eq uri_for('/report/moduleinventory')->path
        or index( request->path,
            uri_for('/ajax/content/report/moduleinventory')->path ) == 0
        );

    # used in the search sidebar template to set selected items
    foreach my $opt (qw/class/) {
        my $p = (
            ref [] eq ref param($opt)
            ? param($opt)
            : ( param($opt) ? [ param($opt) ] : [] )
        );
        $tokens->{"${opt}_lkp"} = { map { $_ => 1 } @$p };
    }
};

get '/ajax/content/report/moduleinventory/data' => require_login sub {
    send_error( 'Missing parameter', 400 )
        unless ( param('draw') && param('draw') =~ /\d+/ );

    my $rs = schema('netdisco')->resultset('DeviceModule');
    $rs = $rs->search( { -bool => 'fru' } ) if param('fruonly');

    if ( param('device') ) {
        my @ips = schema('netdisco')->resultset('Device')
            ->search_fuzzy( param('device') )->get_column('ip')->all;

        params->{'ips'} = \@ips;
    }

    $rs = $rs->search_by_field( scalar params )->columns(
        [   'ip',     'description', 'name',   'class',
            'type',   'serial',      'hw_ver', 'fw_ver',
            'sw_ver', 'model'
        ]
        )->search(
        {},
        {   '+columns' => [qw/ device.dns device.name /],
            join       => 'device',
            collapse   => 1,
        }
        );

    my $exp_params = expand_hash( scalar params );

    my $recordsTotal = $rs->count;

    my @data = $rs->get_datatables_data($exp_params)->hri->all;

    my $recordsFiltered = $rs->get_datatables_filtered_count($exp_params);

    content_type 'application/json';
    return to_json(
        {   draw            => int( param('draw') ),
            recordsTotal    => int($recordsTotal),
            recordsFiltered => int($recordsFiltered),
            data            => \@data,
        }
    );
};

get '/ajax/content/report/moduleinventory' => require_login sub {

    my $has_opt = List::MoreUtils::any { param($_) }
    qw/device description name type model serial class/;

    my $rs = schema('netdisco')->resultset('DeviceModule');
    $rs = $rs->search( { -bool => 'fru' } ) if param('fruonly');
    my @results;

    if ( $has_opt && !request->is_ajax ) {

        if ( param('device') ) {
            my @ips = schema('netdisco')->resultset('Device')
                ->search_fuzzy( param('device') )->get_column('ip')->all;

            params->{'ips'} = \@ips;
        }

        @results = $rs->search_by_field( scalar params )->columns(
            [   'ip',     'description', 'name',   'class',
                'type',   'serial',      'hw_ver', 'fw_ver',
                'sw_ver', 'model'
            ]
            )->search(
            {},
            {   '+columns' => [qw/ device.dns device.name /],
                join       => 'device',
                collapse   => 1,
            }
            )->hri->all;

        return unless scalar @results;
    }
    elsif ( !$has_opt ) {
        @results = $rs->search(
            { class => { '!=', undef } },
            {   select   => [ 'class', { count => 'class' } ],
                as       => [qw/ class count /],
                group_by => [qw/ class /]
            }
        )->order_by( { -desc => 'count' } )->hri->all;

        return unless scalar @results;
    }

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/moduleinventory.tt',
            { results => $json, opt => $has_opt },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/moduleinventory_csv.tt',
            { results => \@results, opt => $has_opt },
            { layout => undef };
    }
};

1;
