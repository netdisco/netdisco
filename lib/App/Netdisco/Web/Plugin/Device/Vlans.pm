package App::Netdisco::Web::Plugin::Device::Vlans;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

#use App::Netdisco::Util::Web (); # for sort_module
use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'vlans', label => 'Vlans' });

ajax '/ajax/content/device/vlans' => require_login sub {
    my $q = param('q');

    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);
    my @results = $device->vlans->search( {}, { order_by => 'vlan' } )->hri->all;

    return unless scalar @results;

    # sort modules (empty set would be a 'no records' msg)
    #my $results = &App::Netdisco::Util::Web::sort_vlans( \@set );
    #return unless scalar %$results;


    if (request->is_ajax) {
      my $json = to_json( \@results );
      template 'ajax/device/vlans.tt', { results => $json },
        { layout => undef };
    }

#    content_type('text/html');
#    template 'ajax/device/vlans.tt', {
#      nodes => $results,
#    }, { layout => undef };
};

true;
