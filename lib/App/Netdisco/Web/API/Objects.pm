package App::Netdisco::Web::API::Objects;

use Dancer ':syntax';
use Dancer::Plugin::Res;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

swagger_path {
  tags => ['Objects'],
  description => 'Returns a row from the device table',
  parameters  => [
    device => {
      description => 'Canonical IP of the Device. Use Search methods to find this.',
      required => 1,
      in => 'path',
    },
  ],
  responses => { default => {} },
}, get '/api/v1/device/:device' => require_role api => sub {
  my $dev = params->{device};
  my $device = schema('netdisco')->resultset('Device')
    ->find($dev) or send_error('Bad Device', 404);
  return to_json $device->TO_JSON;
};

true;
