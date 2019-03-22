package App::Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;

use Dancer::Plugin::Swagger;

# setup for swagger API
my $swagger = Dancer::Plugin::Swagger->instance->doc;
$swagger->{schemes} = ['http','https'];
$swagger->{consumes} = 'application/json';
$swagger->{produces} = 'application/json';
$swagger->{tags} = [
  {name => 'General'},
  {name => 'Devices',
    description => 'Operations relating to Devices (switches, routers, etc)'},
  {name => 'Nodes',
    description => 'Operations relating to Nodes (end-stations such as printers)'},
  {name => 'NodeIPs',
    description => 'Operations relating to MAC-IP mappings (IPv4 ARP and IPv6 Neighbors)'},
];
$swagger->{securityDefinitions} = {
  APIKeyHeader =>
    { type => 'apiKey', name => 'Authorization', in => 'header' },
  BasicAuth =>
    { type => 'basic' },
};
$swagger->{security} = [ { APIKeyHeader => [] } ];

# workaround for Swagger plugin weird response body
hook 'after' => sub {
    my $r = shift; # a Dancer::Response

    if (request->path eq '/swagger.json') {
        $r->content( to_json( $r->content ) );
        header('Content-Type' => 'application/json');
    }
};

# forward API calls to AJAX route handlers
any '/api/:type/:identifier/:method' => require_login sub {
    pass unless setting('api_enabled')
      ->{ params->{'type'} }->{ params->{'method'} };

    my $target =
      sprintf '/ajax/content/%s/%s', params->{'type'}, params->{'method'};
    forward $target, { tab => params->{'method'}, q => params->{'identifier'} };
};

true;
