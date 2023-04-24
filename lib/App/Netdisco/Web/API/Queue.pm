package App::Netdisco::Web::API::Queue;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use Try::Tiny;

swagger_path {
  tags => ['Queue'],
  path => (setting('api_base') || '').'/queue/jobs',
  description => 'Return jobs in the queue, optionally filtered by fields',
  parameters  => [
    limit => {
      description => 'Maximum number of Jobs to return',
      type => 'integer',
      default => (setting('jobs_qdepth') || 50),
    },
    device => {
      description => 'IP address field of the Job',
    },
    port => {
      description => 'Port field of the Job',
    },
    action => {
      description => 'Action field of the Job',
    },
    status => {
      description => 'Status field of the Job',
    },
    username => {
      description => 'Username of the Job submitter',
    },
    userip => {
      description => 'IP address of the Job submitter',
    },
    backend => {
      description => 'Backend instance assigned the Job',
    },
  ],
  responses => { default => {} },
}, get '/api/v1/queue/jobs' => require_role api_admin => sub {
  my @set = schema(vars->{'tenant'})->resultset('Admin')->search({
    ( param('device')   ? ( device   => param('device') )   : () ),
    ( param('port')     ? ( port     => param('port') )     : () ),
    ( param('action')   ? ( action   => param('action') )   : () ),
    ( param('status')   ? ( status   => param('status') )   : () ),
    ( param('username') ? ( username => param('username') ) : () ),
    ( param('userip')   ? ( userip   => param('userip') )   : () ),
    ( param('backend')  ? ( backend  => param('backend') )  : () ),
    -or => [
      { 'log' => undef },
      { 'log' => { '-not_like' => 'duplicate of %' } },
    ],
  }, {
    order_by => { -desc => [qw/entered device action/] },
    rows     => (param('limit') || setting('jobs_qdepth') || 50),
  })->with_times->hri->all;

  return to_json \@set;
};

swagger_path {
  tags => ['Queue'],
  path => (setting('api_base') || '').'/queue/jobs',
  description => 'Delete jobs and skiplist entries, optionally filtered by fields',
  parameters  => [
    device => {
      description => 'IP address field of the Job',
    },
    port => {
      description => 'Port field of the Job',
    },
    action => {
      description => 'Action field of the Job',
    },
    status => {
      description => 'Status field of the Job',
    },
    username => {
      description => 'Username of the Job submitter',
    },
    userip => {
      description => 'IP address of the Job submitter',
    },
    backend => {
      description => 'Backend instance assigned the Job',
    },
  ],
  responses => { default => {} },
}, del '/api/v1/queue/jobs' => require_role api_admin => sub {
  my $gone = schema(vars->{'tenant'})->resultset('Admin')->search({
    ( param('device')   ? ( device   => param('device') )   : () ),
    ( param('port')     ? ( port     => param('port') )     : () ),
    ( param('action')   ? ( action   => param('action') )   : () ),
    ( param('status')   ? ( status   => param('status') )   : () ),
    ( param('username') ? ( username => param('username') ) : () ),
    ( param('userip')   ? ( userip   => param('userip') )   : () ),
    ( param('backend')  ? ( backend  => param('backend') )  : () ),
  })->delete;

  schema(vars->{'tenant'})->resultset('DeviceSkip')->search({
    ( param('device')  ? ( device    => param('device') )  : () ),
    ( param('action')  ? ( actionset => { '&&' => \[ 'ARRAY[?]', param('action') ] } ) : () ),
    ( param('backend') ? ( backend   => param('backend') ) : () ),
  })->delete;

  return to_json { deleted => ($gone || 0)};
};

true;
