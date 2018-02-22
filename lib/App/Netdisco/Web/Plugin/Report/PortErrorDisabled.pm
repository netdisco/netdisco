package App::Netdisco::Web::Plugin::Report::PortErrorDisabled;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category     => 'Port',
        tag          => 'porterrordisabled',
        label        => 'Error Disabled Ports',
        provides_csv => 1,
    }
);

get '/ajax/content/report/porterrordisabled' => require_login sub {
    my @results = schema('netdisco')->resultset('DevicePorts')
      ->with_properties->search({
          'properties.error_disable_cause' => { '!=' => undef },
      })->hri->all;
#        {   select => [ 'ip', 'dns', 'name' ],
#            join       => { 'ports' => [ 'wireless', 'nodes' ] },
#            '+columns' => [
#                { 'port'        => 'ports.port' },
#                { 'description' => 'ports.name' },
#                { 'mac_count'   => { count => 'nodes.mac' } },
#            ],
#            group_by => [qw/me.ip me.dns me.name ports.port ports.name/],
#            having   => \[ 'count(nodes.mac) > ?', [ count => 1 ] ],
#            order_by => { -desc => [qw/count/] },
#        }

    return unless scalar @results;

    if ( request->is_ajax ) {
        my $json = to_json (\@results);
        template 'ajax/report/porterrordisabled.tt', { results => $json },
            { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/porterrordisabled.tt',
            { results => \@results, },
            { layout  => undef };
    }
};

1;
