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

ajax '/ajax/data/device/:ip/snmptree/:base' => require_login sub {
    my $device = try { schema('netdisco')->resultset('Device')
                                         ->find( param('ip') ) }
       or send_error('Bad Device', 404);

    my $base = param('base');
    $base =~ m/^\.1\.3\.6\.1(\.\d+)*$/ or send_error('Bad OID Base', 404);
    my @parts = grep {length} split m/\./, $base;

    my %kids = map { ($base .'.'. $_->{part}) => $_ }
               schema('netdisco')->resultset('Virtual::OidChildren')
                                 ->search({}, { bind => [
                                     (scalar @parts + 1),
                                     (scalar @parts + 2),
                                     (scalar @parts + 1),
                                     (scalar @parts + 1),
                                     $device->ip,
                                     $device->ip,
                                     $base,
                                 ] })->hri->all;

    my %meta = map { ('.'. join '.', @{$_->{oid_parts}}) => $_ }
               schema('netdisco')->resultset('Virtual::FilteredSNMPObject')
                                 ->search({}, { bind => [
                                     $base,
                                     (scalar @parts + 1),
                                     [ map {$_->{part}} values %kids ],
                                     (scalar @parts + 1),
                                 ] })->hri->all;

    my @items = map {{
        id => $_,
        text => ($meta{$_}->{leaf} .' ('. $kids{$_}->{part} .')'),
        children => \1,
      }} sort keys %kids;

    content_type 'application/json';
    to_json \@items
};

true;
