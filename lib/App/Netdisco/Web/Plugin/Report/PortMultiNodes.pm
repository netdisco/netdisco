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
        api_endpoint => 1,
        api_parameters => [
          vlan => {
            description => 'Filter by VLAN',
            type => 'integer',
          },
        ],
    }
);

get '/ajax/content/report/portmultinodes' => require_login sub {
    my @results = schema(vars->{'tenant'})->resultset('Device')->search(
        {   'ports.remote_ip' => undef,
            (param('vlan') ?
              ('ports.vlan' => param('vlan'), 'nodes.vlan' => param('vlan')) : ()),
            'nodes.active'    => 1,
            'wireless.port'   => undef
        },
        {   select => [ 'ip', 'dns', 'name' ],
            join       => { 'ports' => [ 'wireless', 'nodes' ] },
            '+columns' => [
                { 'port'        => 'ports.port' },
                { 'description' => 'ports.name' },
                { 'mac_count'   => { count => 'nodes.mac' } },
            ],
            group_by => [qw/me.ip me.dns me.name ports.port ports.name/],
            having   => \[ 'count(nodes.mac) > ?', [ count => 1 ] ],
            order_by => { -desc => [qw/count/] },
        }
    )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json (\@results);
        template 'ajax/report/portmultinodes.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portmultinodes_csv.tt',
            { results => \@results, }, { layout => 'noop' };
    }
};

1;
