package App::Netdisco::Web::Plugin::Report::DeviceAddrNoDNS;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Device',
        tag          => 'deviceaddrnodns',
        label        => 'Addresses without DNS Entries',
        provides_csv => 1,
    }
);

get '/ajax/content/report/deviceaddrnodns' => require_login sub {
    my @results = schema('netdisco')->resultset('Device')->search(
        { 'device_ips.dns' => undef },
        {   select       => [ 'ip', 'dns', 'name', 'location', 'contact' ],
            join         => [qw/device_ips/],
            '+columns' => [ { 'alias' => 'device_ips.alias' }, ],
            order_by => { -asc => [qw/me.ip device_ips.alias/] },
        }
    )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json (\@results);
        template 'ajax/report/deviceaddrnodns.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/deviceaddrnodns_csv.tt',
            { results => \@results, },
            { layout  => undef };
    }
};

1;
