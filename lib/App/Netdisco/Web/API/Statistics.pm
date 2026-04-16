package App::Netdisco::Web::API::Statistics;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use Try::Tiny;

swagger_path {
  tags => ['General'],
  path => (setting('api_base') || '').'/statistics',
  description => 'Returns the latest row from the statistics table',
  parameters => [],
  responses => { default => {} },

}, get '/api/v1/statistics' => require_role api => sub {
  my $stats = try {
    schema(vars->{'tenant'})->resultset('Statistics')
      ->search(undef, { order_by => { -desc => 'day' }, rows => 1 })->first
  } or send_error('No statistics available', 404);

  return to_json $stats->TO_JSON;
};

true;
