package App::Netdisco::Web::Plugin::Report::NodeMultiIPs;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Node',
        tag          => 'nodemultiips',
        label        => 'Nodes with multiple active IP addresses',
        provides_csv => 1,
    }
);

get '/ajax/content/report/nodemultiips' => require_login sub {
    my @results = schema('netdisco')->resultset('Node')->search(
        {},
        {   select     => [ 'mac', 'switch', 'port' ],
            join       => [qw/device ips oui/],
            '+columns' => [
                { 'dns'      => 'device.dns' },
                { 'name'     => 'device.name' },
                { 'ip_count' => { count => 'ips.ip' } },
                { 'vendor'   => 'oui.company' }
            ],
            group_by => [
                qw/ me.mac me.switch me.port device.dns device.name oui.company/
            ],
            having => \[ 'count(ips.ip) > ?', [ count => 1 ] ],
            order_by => { -desc => [qw/count/] },
        }
    )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/nodemultiips.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/nodemultiips_csv.tt',
            { results => \@results },
            { layout  => undef };
    }
};

1;
