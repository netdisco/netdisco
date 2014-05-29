package App::Netdisco::Web::Plugin::Report::HalfDuplex;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Port',
        tag          => 'halfduplex',
        label        => 'Ports in Half Duplex Mode',
        provides_csv => 1,
    }
);

get '/ajax/content/report/halfduplex' => require_login sub {
    my $format = param('format');
    my @results
        = schema('netdisco')->resultset('DevicePort')
        ->columns( [qw/ ip port name duplex /] )->search(
        { up => 'up', duplex => { '-ilike' => 'half' } },
        {   '+columns' => [qw/ device.dns device.name /],
            join       => [qw/ device /],
            collapse   => 1,
        }
        )->order_by( [qw/ device.dns port /] )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/halfduplex.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/halfduplex_csv.tt',
            { results => \@results },
            { layout  => undef };
    }
};

1;
