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
    my $set
        = schema('netdisco')->resultset('Device')
        ->search( {},
        { order_by => [qw/ location name ip vendor model /], } );
    return unless $set->count;

    if ( request->is_ajax ) {
        template 'ajax/report/devicebylocation.tt', { results => $set, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/devicebylocation_csv.tt', { results => $set, },
            { layout => undef };
    }
};

true;
