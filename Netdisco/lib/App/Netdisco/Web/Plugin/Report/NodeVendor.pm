package App::Netdisco::Web::Plugin::Report::NodeVendor;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

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

get '/ajax/content/report/nodevendor' => require_login sub {

    my $vendor = param('vendor');

    my $rs = schema('netdisco')->resultset('Node');

    if ( defined $vendor ) {

        my $match = $vendor eq 'blank' ? undef : $vendor;

        $rs = $rs->search( { 'oui.abbrev' => $match },
            {   '+columns' => [qw/ device.dns device.name oui.abbrev /],
                join       => [qw/ oui device /],
                collapse   => 1,
            });

        unless ( param('archived') ) {
            $rs = $rs->search( { -bool => 'me.active' } );
        }
    }
    else {
        $rs = $rs->search(
            { -bool => 'me.active' },
            {   join     => 'oui',
                select   => [ 'oui.abbrev', { count => 'me.mac' } ],
                as       => [qw/ vendor count /],
                group_by => [qw/ oui.abbrev /]
            }
        )->order_by( { -desc => 'count' } );
    }

    my @results = $rs->hri->all;
    return unless scalar @results;

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
