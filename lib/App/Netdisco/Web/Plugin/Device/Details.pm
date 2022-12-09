package App::Netdisco::Web::Plugin::Device::Details;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'details', label => 'Details' });

# device details table
ajax '/ajax/content/device/details' => require_login sub {
    my $q = param('q');
    my $device = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    my @results
        = schema(vars->{'tenant'})->resultset('Device')
        ->search({ 'me.ip' => $device->ip },
          {
            '+select' => ['snapshot.ip'],
            '+as' => ['has_snapshot'],
            join => 'snapshot',
          },
        )->with_times->with_custom_fields->hri->all;

    my @power
        = schema(vars->{'tenant'})->resultset('DevicePower')
        ->search( { 'me.ip' => $device->ip } )->with_poestats->hri->all;

    my @interfaces
        = schema(vars->{'tenant'})->resultset('Device')
        ->find($device->ip)
        ->device_ips->hri->all;

    content_type('text/html');
    template 'ajax/device/details.tt', {
      d => $results[0], p => \@power, interfaces => \@interfaces,
    }, { layout => undef };
};

1;
