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
    }
);

get '/ajax/content/report/apclients' => require_login sub {
    my @results = schema('netdisco')->resultset('Device')->search(
        { 'nodes.time_last' => { '>=', \'me.last_macsuck' } },
        {   result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            select       => [ 'ip', 'dns', 'name', 'model', 'location' ],
            join       => { 'ports' => { 'wireless' => 'nodes' } },
            '+columns' => [
                { 'port'        => 'ports.port' },
                { 'description' => 'ports.name' },
                { 'mac_count'   => { count => 'nodes.mac' } },
            ],
            group_by => [
                'me.ip',       'me.dns',     'me.name',     'me.model',
                'me.location', 'ports.port', 'ports.descr', 'ports.name'
            ],
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
