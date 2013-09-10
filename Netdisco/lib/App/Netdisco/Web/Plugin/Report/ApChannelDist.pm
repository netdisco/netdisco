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

ajax '/ajax/content/report/apchanneldist' => require_login sub {
    my $set = schema('netdisco')->resultset('DevicePortWireless')->search(
        { channel => { '!=', '0' } },
        {   select   => [ 'channel', { count => 'channel' } ],
            as       => [qw/ channel ch_count /],
            group_by => [qw/channel/],
            order_by => { -desc => [qw/count/] },
        },
    );

    return unless $set->count;

    content_type('text/html');
    template 'ajax/report/apchanneldist.tt', { results => $set, },
        { layout => undef };
};

true;
