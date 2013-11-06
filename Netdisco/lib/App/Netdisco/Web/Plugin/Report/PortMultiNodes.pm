package App::Netdisco::Web::Plugin::Report::PortMultiNodes;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Port',
        tag          => 'portmultinodes',
        label        => 'Ports with multiple nodes attached',
        provides_csv => 1,
    }
);

get '/ajax/content/report/portmultinodes' => require_login sub {
    my @results = schema('netdisco')->resultset('Device')->search(
        { 'ports.remote_ip' => undef, 'nodes.active' => 1 },
        {   result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            select       => [ 'ip', 'dns', 'name' ],
            join       => { 'ports' => 'nodes' },
            '+columns' => [
                { 'port'        => 'ports.port' },
                { 'description' => 'ports.name' },
                { 'mac_count'   => { count => 'nodes.mac' } },
            ],
            group_by => [qw/me.ip me.dns me.name ports.port ports.name/],
            having   => \[ 'count(nodes.mac) > ?', [ count => 1 ] ],
            order_by => { -desc => [qw/count/] },
        }
    )->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/report/portmultinodes.tt', { results => \@results, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portmultinodes_csv.tt',
            { results => \@results, },
            { layout  => undef };
    }
};

1;
