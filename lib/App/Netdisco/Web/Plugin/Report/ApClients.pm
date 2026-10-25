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
    my @results = schema(vars->{'tenant'})->resultset('Node')->search(
        { 'wireless_port.port' => { '!=', undef },
          'me.time_last' => { '>=', \'device.last_macsuck' },
        },
        {   select => [qw/device.ip device.dns device.name device.model device_port.port device_port.name device_port.type wireless.ssid/],
            as => [qw/ip dns name model port port_name port_type ssid/],
            join       => [qw/device device_port wireless_port wireless/],
            '+columns' => [
                { 'mac_count' => { count => 'me.mac' } },
            ],
            group_by => [
                'device.ip', 'device.dns', 'device.name', 'device.model',
                'device_port.port', 'device_port.name', 'device_port.type', 'wireless.ssid',
            ],
            order_by => { -asc => [qw/device.name device_port.name wireless.ssid/] },
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
