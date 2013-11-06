package App::Netdisco::Web::Plugin::Report::PortBlocking;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Port',
        tag          => 'portblocking',
        label        => 'Ports that are blocking',
        provides_csv => 1,
    }
);

get '/ajax/content/report/portblocking' => require_login sub {
    my @results = schema('netdisco')->resultset('Device')->search(
        { 'stp' => [ 'blocking', 'broken' ], 'up' => { '!=', 'down' } },
        {   result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            select       => [ 'ip', 'dns', 'name' ],
            join         => ['ports'],
            '+columns'   => [
                { 'port'        => 'ports.port' },
                { 'description' => 'ports.name' },
                { 'stp'         => 'ports.stp' },
            ],
            order_by => { -asc => [qw/me.ip ports.port/] },
        }
    )->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/report/portblocking.tt', { results => \@results, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portblocking_csv.tt',
            { results => \@results, },
            { layout  => undef };
    }
};

1;
