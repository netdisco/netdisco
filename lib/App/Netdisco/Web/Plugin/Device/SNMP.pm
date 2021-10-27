package App::Netdisco::Web::Plugin::Device::SNMP;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'snmp', label => 'SNMP' });

get '/ajax/content/device/snmp' => require_login sub {
    my $q = param('q');

    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);
#    my @results = $device->vlans->search(
#      { vlan => { '>' => 0 } }, { order_by => 'vlan' } )->hri->all;
#
#    return unless scalar @results;

#    if (request->is_ajax) {
#      my $json = to_json( \@results );
      template 'ajax/device/snmp.tt',# { results => $json },
        { layout => 'noop' };
#    }
#    else {
#      header( 'Content-Type' => 'text/comma-separated-values' );
#      template 'ajax/device/vlans_csv.tt', { results => \@results },
#        { layout => 'noop' };
#    }
};

true;
