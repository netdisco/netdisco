package App::Netdisco::Web::Plugin::Report::PortAdminDown;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Port',
        tag          => 'portadmindown',
        label        => 'Ports administratively disabled',
        provides_csv => 1,
    }
);

get '/ajax/content/report/portadmindown' => require_login sub {
    my @results = schema('netdisco')->resultset('Device')->search(
        { 'up_admin' => 'down' },
        {   result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            select       => [ 'ip', 'dns', 'name' ],
            join       => [ 'ports' ],
            '+columns' => [
                { 'port'        => 'ports.port' },
                { 'description' => 'ports.name' },
                { 'up_admin'    => 'ports.up_admin' },
            ],
            order_by => { -asc => [qw/me.ip ports.port/] },
        }
    )->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/report/portadmindown.tt', { results => \@results, },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/portadmindown_csv.tt',
            { results => \@results, },
            { layout  => undef };
    }
};

1;
