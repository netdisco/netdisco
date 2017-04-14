package App::Netdisco::Web::Plugin::Report::NodeVendor;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::ExpandParams 'expand_hash';

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Node',
        tag          => 'nodevendor',
        label        => 'Node Vendor Inventory',
        provides_csv => 1,
    }
);

hook 'before_template' => sub {
    my $tokens = shift;

    return
        unless (
        request->path eq uri_for('/report/nodevendor')->path
        or index( request->path,
            uri_for('/ajax/content/report/nodevendor')->path ) == 0
        );

    # used in the search sidebar template to set selected items
    foreach my $opt (qw/vendor/) {
        my $p = (
            ref [] eq ref param($opt)
            ? param($opt)
            : ( param($opt) ? [ param($opt) ] : [] )
        );
        $tokens->{"${opt}_lkp"} = { map { $_ => 1 } @$p };
    }
};

get '/ajax/content/report/nodevendor/data' => require_login sub {
    send_error( 'Missing parameter', 400 )
        unless ( param('draw') && param('draw') =~ /\d+/ );

    my $vendor = param('vendor');

    my $rs = schema('netdisco')->resultset('Node');

        my $match = $vendor eq 'blank' ? undef : $vendor;

        $rs = $rs->search( { 'oui.abbrev' => $match },
            {   '+columns' => [qw/ device.dns device.name oui.abbrev /],
                join       => [qw/ oui device /],
                collapse   => 1,
            });

        unless ( param('archived') ) {
            $rs = $rs->search( { -bool => 'me.active' } );
        }

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

get '/ajax/content/report/nodevendor' => require_login sub {

    my $vendor = param('vendor');

    my $rs = schema('netdisco')->resultset('Node');
    my @results;
    
    if ( defined $vendor && !request->is_ajax ) {

        my $match = $vendor eq 'blank' ? undef : $vendor;

        $rs = $rs->search( { 'oui.abbrev' => $match },
            {   '+columns' => [qw/ device.dns device.name oui.abbrev /],
                join       => [qw/ oui device /],
                collapse   => 1,
            });

        unless ( param('archived') ) {
            $rs = $rs->search( { -bool => 'me.active' } );
        }

        @results = $rs->hri->all;
        return unless scalar @results;
    }
    elsif ( !defined $vendor ) {
        $rs = $rs->search(
            { },
            {   join     => 'oui',
                select   => [ 'oui.abbrev', { count => 'me.mac' } ],
                as       => [qw/ vendor count /],
                group_by => [qw/ oui.abbrev /]
            }
        )->order_by( { -desc => 'count' } );

        unless ( param('archived') ) {
            $rs = $rs->search( { -bool => 'me.active' } );
        }
        
        @results = $rs->hri->all;
        return unless scalar @results;
    }

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/nodevendor.tt',
            { results => $json, opt => $vendor },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/nodevendor_csv.tt',
            { results => \@results, opt => $vendor },
            { layout => undef };
    }
};

1;
