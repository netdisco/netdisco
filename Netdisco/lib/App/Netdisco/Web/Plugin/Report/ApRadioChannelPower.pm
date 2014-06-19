package App::Netdisco::Web::Plugin::Report::ApRadioChannelPower;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::ExpandParams 'expand_hash';

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Wireless',
        tag          => 'apradiochannelpower',
        label        => 'Access Point Radios Channel and Power',
        provides_csv => 1,
    }
);

get '/ajax/content/report/apradiochannelpower/data' => require_role admin =>
    sub {
    send_error( 'Missing parameter', 400 )
        unless ( param('draw') && param('draw') =~ /\d+/ );

    my $rs = schema('netdisco')->resultset('Virtual::ApRadioChannelPower');

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

get '/ajax/content/report/apradiochannelpower' => require_login sub {

    if ( request->is_ajax ) {
        template 'ajax/report/apradiochannelpower.tt', {},
            { layout => undef };
    }

    else {
        my @results
            = schema('netdisco')->resultset('Virtual::ApRadioChannelPower')
            ->hri->all;

        return unless scalar @results;

        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/apradiochannelpower_csv.tt',
            { results => \@results, },
            { layout  => undef };
    }
};

1;
