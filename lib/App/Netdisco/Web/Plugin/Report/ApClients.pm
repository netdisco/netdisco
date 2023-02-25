package App::Netdisco::Web::Plugin::Report::ApClients;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Wireless',
        tag          => 'apclients',
        label        => 'Access Point Client Count',
        provides_csv => 1,
        api_endpoint => 1,
    }
);

get '/ajax/content/report/apclients' => require_login sub {
    my @results = schema(vars->{'tenant'})->resultset('Device')->search(
        { 'nodes.time_last' => { '>=', \'me.last_macsuck' },
          'ports.port' => { '-in' => schema(vars->{'tenant'})->resultset('DevicePortWireless')->get_column('port')->as_query },
        },
        {   select => [ 'ip', 'model', 'ports.port', 'ports.name', 'ports.type' ],
            join       => { 'ports' =>  'nodes' },
            '+columns' => [
                { 'mac_count' => { count => 'nodes.mac' } },
            ],
            group_by => [
                'me.ip', 'me.model', 'ports.port', 'ports.name', 'ports.type',
            ],
            order_by => { -asc => [qw/ports.name ports.type/] },
        }
    )->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json( \@results );
        template 'ajax/report/apclients.tt', { results => $json }, { layout => 'noop' };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/apclients_csv.tt',
            { results => \@results }, { layout => 'noop' };
    }
};

1;
