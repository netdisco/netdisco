package App::Netdisco::Web::Plugin::Device::SNMP;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use Try::Tiny;

register_device_tab({ tag => 'snmp', label => 'SNMP' });

get '/ajax/content/device/snmp' => require_login sub {
    my $q = param('q');

    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    template 'ajax/device/snmp.tt', { device => $device->ip },
      { layout => 'noop' };
};

# handler for base request at 1.3.6.1
ajax '/ajax/data/device/:ip/snmptree/' => require_login sub {
    my $device = try { schema('netdisco')->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    # get children of 1.3.6.1
    my $kids = schema('netdisco')->resultset('Virtual::OidChildren')
                                 ->search({}, { bind => [ $device->ip, [1,3,6,1] ] }); 

    my @items = (map {{
        id => '1.3.6.1.'. $_->part,
        text => '1.3.6.1.'. $_->part,
        children => \1,
      }} $kids->all);

    content_type 'application/json';
    to_json \@items
};

# handler for any subsequent request
ajax '/ajax/data/device/:ip/snmptree/:base' => require_login sub {
    content_type 'application/json';
    to_json ['foo', { text => 'bar', state => { opened => 'true', selected => 'true' }, children => [ { text => 'child 1' }, 'child 2' ] }];
};

true;
