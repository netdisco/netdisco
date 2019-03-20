package App::Netdisco::Web::Plugin::Device::Details;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Swagger;

use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'details', label => 'Details' });

# forward API call to AJAX route handler
swagger_path {
    description => 'Get properties and power details for a device.',
    tags => ['Devices'],
    parameters => [
        identifier => {in => 'path', required => 1, type => 'string' },
    ],
    responses => { default => { examples => {
        # TODO document fields returned
        'application/json' => { device => {} },
    } } },
},
get '/api/device/:identifier' => require_login sub {
    vars->{'is_api'} = 1;
    forward '/ajax/content/device/details',
      { tab => 'details', q => params->{'identifier'} };
};

# device details table
get '/ajax/content/device/details' => require_login sub {
    my $q = param('q');
    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or return bang('Bad device', 400);

    my @results
        = schema('netdisco')->resultset('Device')
        ->search( { 'me.ip' => $device->ip } )->with_times()
        ->hri->all;
    
    my @power
        = schema('netdisco')->resultset('DevicePower')
        ->search( { 'me.ip' => $device->ip } )->with_poestats->hri->all;

    delete $results[0]->{'snmp_comm'};
    $results[0]->{'power'} = \@power;

    if (vars->{'is_api'}) {
        content_type('application/json');
        to_json { device => $results[0] };
    }
    else {
        content_type('text/html');
        template 'ajax/device/details.tt', {
          d => $results[0], p => \@power
        }, { layout => undef };
    }
};

true;
