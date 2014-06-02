package App::Netdisco::Web::Plugin::Report::ApChannelDist;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Wireless',
        tag          => 'apchanneldist',
        label        => 'Access Point Channel Distribution',
        provides_csv => 1,
    }
);

get '/ajax/content/report/apchanneldist' => require_login sub {
    my @results = schema('netdisco')->resultset('DevicePortWireless')->search(
        { channel => { '!=', '0' } },
        {   select   => [ 'channel', { count => 'channel' } ],
            as       => [qw/ channel ch_count /],
            group_by => [qw/channel/],
            order_by => { -desc => [qw/count/] },
        },
    )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/apchanneldist.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/apchanneldist_csv.tt', { results => \@results },
            { layout => undef };
    }
};

1;
