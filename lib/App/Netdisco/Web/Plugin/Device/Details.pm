package App::Netdisco::Web::Plugin::Device::Details;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Swagger;

use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'details', label => 'Details' });

# device details table
swagger_path {
    description => 'Get properties and power details for a device.',
    path => '/api/device/{identifier}/details',
    tags => ['Devices'],
    parameters => [
        { name => 'identifier', in => 'path', required => 1, type => 'string' },
    ],
    responses => { default => { examples => {
        'application/json' => { device => {}, power => {} },
    } } },
},
get '/ajax/content/device/details' => require_login sub {
    my $q = param('q');
    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    my @results
        = schema('netdisco')->resultset('Device')
        ->search( { 'me.ip' => $device->ip } )->with_times()
        ->hri->all;
    
    my @power
        = schema('netdisco')->resultset('DevicePower')
        ->search( { 'me.ip' => $device->ip } )->with_poestats->hri->all;

    if (vars->{'is_api'}) {
        content_type('application/json');
        # TODO merge power into device details
        # TODO remove sensitive data (community)
        to_json { device => $results[0], power => \@power };
    }
    else {
        content_type('text/html');
        template 'ajax/device/details.tt', {
          d => $results[0], p => \@power
        }, { layout => undef };
    }
};

1;
