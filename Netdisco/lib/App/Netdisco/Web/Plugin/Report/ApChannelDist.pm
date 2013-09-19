package App::Netdisco::Web::Plugin::Report::ApChannelDist;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category => 'Wireless',
        tag      => 'apchanneldist',
        label    => 'Access Point Channel Distribution',
    }
);

sub get_rs_apchdist {
    my $set = schema('netdisco')->resultset('DevicePortWireless')->search(
        { channel => { '!=', '0' } },
        {   select   => [ 'channel', { count => 'channel' } ],
            as       => [qw/ channel ch_count /],
            group_by => [qw/channel/],
            order_by => { -desc => [qw/count/] },
        },
    );
    return $set;
}

ajax '/ajax/content/report/apchanneldist' => require_login sub {
    my $set = get_rs_apchdist();

    return unless $set->count;

    content_type('text/html');
    template 'ajax/report/apchanneldist.tt', { results => $set, },
        { layout => undef };
};

get '/ajax/content/report/apchanneldist' => require_login sub {
    my $format = param('format');
    my $set    = get_rs_apchdist();

    return unless $set->count;

    if ( $format eq 'csv' ) {

        header( 'Content-Type' => 'text/comma-separated-values' );
        header( 'Content-Disposition' =>
                "attachment; filename=\"apchanneldist.csv\"" );
        template 'ajax/report/apchanneldist_csv.tt', { results => $set, },
            { layout => undef };
    }
    else {
        return;
    }
};

true;
