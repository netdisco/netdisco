package App::Netdisco::Web::Plugin::Report::DeviceByLocation;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Device',
        tag          => 'devicebylocation',
        label        => 'By Location',
        provides_csv => 1,
    }
);

get '/ajax/content/report/devicebylocation' => require_login sub {
    my @results
        = schema('netdisco')->resultset('Device')
        ->columns(  [qw/ ip dns name location vendor model /] )
        ->order_by( [qw/ location name ip vendor model /] )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/devicebylocation.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/devicebylocation_csv.tt',
            { results => \@results },
            { layout  => undef };
    }
};

1;
