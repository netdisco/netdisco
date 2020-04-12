package App::Netdisco::Web::API::Objects;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use Try::Tiny;

swagger_path {
  tags => ['Objects'],
  description => 'Returns a row from the device table',
  parameters  => [
    ip => {
      description => 'Canonical IP of the Device. Use Search methods to find this.',
      required => 1,
      in => 'path',
    },
  ],
  responses => { default => {} },
}, get '/api/v1/object/device/:ip' => require_role api => sub {
  my $device = try { schema('netdisco')->resultset('Device')
    ->find( params->{ip} ) } or send_error('Bad Device', 404);
  return to_json $device->TO_JSON;
};

swagger_path {
  tags => ['Objects'],
  description => 'Returns device_port rows for a given device',
  parameters  => [
    ip => {
      description => 'Canonical IP of the Device. Use Search methods to find this.',
      required => 1,
      in => 'path',
    },
  ],
  responses => { default => {} },
}, get '/api/v1/object/device/:ip/ports' => require_role api => sub {
  my $ports = try { schema('netdisco')->resultset('Device')
    ->find( params->{ip} )->ports } or send_error('Bad Device', 404);
  return to_json [ map {$_->TO_JSON} $ports->all ];
};

swagger_path {
  tags => ['Objects'],
  description => 'Returns a row from the device_port table',
  path => '/api/v1/object/device/{ip}/port/{port}',
  parameters  => [
    ip => {
      description => 'Canonical IP of the Device. Use Search methods to find this.',
      required => 1,
      in => 'path',
    },
    port => {
      description => 'Name of the port. Use the ".../device/{ip}/ports" method to find these.',
      required => 1,
      in => 'path',
    },
  ],
  responses => { default => {} },
}, get qr{/api/v1/object/device/(?<ip>.*)/port/(?<port>.*)} => require_role api => sub {
  my $params = captures;
  my $port = try { schema('netdisco')->resultset('DevicePort')
    ->find( $$params{port}, $$params{ip} ) } or send_error('Bad Device or Port', 404);
  return to_json $port->TO_JSON;
};

true;
