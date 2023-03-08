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

    my @interfaces = $device->device_ips->hri->all;

    my @serials = $device->modules->search({
        class => 'chassis',
        -bool => 'fru',
        -and => [
          { serial => { '!=' => '' } },
          { serial => { '!=' => undef } },
        ],
    })->order_by('pos')->get_column('serial')->all;

    content_type('text/html');
    template 'ajax/device/details.tt', {
      d => $results[0], p => \@power,
      interfaces => \@interfaces,
      serials => [sort keys %{ { map {($_ => $_)} (@serials, ($device->serial ? $device->serial : ())) } }],
    }, { layout => undef };
};

1;
