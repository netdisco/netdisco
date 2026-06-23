package App::Netdisco::Web::API::Queue;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::JobQueue 'jq_insert';
use App::Netdisco::Util::DNS 'ipv4_from_hostname';
use NetAddr::IP::Lite;
use Try::Tiny;

swagger_path {
  tags => ['Queue'],
  path => (setting('api_base') || '').'/queue/status',
  description => 'Return counts of jobs by status. queued/running reflect current state; done/failed are optionally scoped by since.',
  parameters => [
    since => {
      in => 'query',
      description => 'Limit done/failed counts to jobs finished within this duration. Examples: 1h, 30m, 2d. Default: all time.',
      required => 0,
    },
  ],
  responses => { default => {} },
}, get '/api/v1/queue/status' => require_role api_admin => sub {
  my $since = params->{since} || '';

  my $since_epoch = undef;
  if ($since =~ /^(\d+)(m|h|d)$/) {
    my ($n, $unit) = ($1, $2);
    my %mul = (m => 60, h => 3600, d => 86400);
    $since_epoch = time - ($n * $mul{$unit});
  }
  elsif ($since) {
    send_error('Invalid since format. Use e.g. 30m, 2h, 7d', 400);
  }

  my $rs = schema(vars->{'tenant'})->resultset('Admin');

  my $since_filter = $since_epoch
    ? { finished => { '>=' => \["to_timestamp(?)", $since_epoch] } }
    : {};

  my $queued  = try { $rs->search({ status => 'queued'  })->count } catch { 0 };
  my $running = try { $rs->search({ status => 'running' })->count } catch { 0 };
  my $done    = try { $rs->search({ status => 'done',  %$since_filter })->count } catch { 0 };
  my $failed  = try { $rs->search({ status => 'error', %$since_filter })->count } catch { 0 };

  return to_json {
    queued  => $queued,
    running => $running,
    done    => $done,
    failed  => $failed,
    since   => ($since || 'all time'),
  };
};

swagger_path {
  tags => ['Queue'],
  path => (setting('api_base') || '').'/queue/backends',
  description => 'Return list of currently active backend names (usually FQDN)',
  responses => { default => {} },
}, get '/api/v1/queue/backends' => require_role api_admin => sub {
  # from 1d988bbf7 this always returns an entry
  my @names = schema(vars->{'tenant'})->resultset('DeviceSkip')
    ->get_distinct_col('backend');

  return to_json \@names;
};

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

swagger_path {
  tags => ['Queue'],
  path => (setting('api_base') || '').'/queue/jobs',
  description => 'Submit jobs to the queue',
  parameters  => [
    jobs => {
      description => 'List of job specifications (action, device?, port?, extra?).',
      default => '[]',
      schema => {
        type => 'array',
        items => {
          type => 'object',
          properties => {
            action => {
              type => 'string',
              required => 1,
              description => 'Job action. Known actions: discover, macsuck, arpnip, nbtstat, delete. Unknown actions are accepted but will fail silently in the backend.',
            },
            device => {
              type => 'string',
              required => 0,
            },
            port => {
              type => 'string',
              required => 0,
            },
            extra => {
              type => 'string',
              required => 0,
              description => 'Optional job parameter. For discover: a plain string or JSON object. Plain string is treated as device_auth_tag_hint. Supported JSON params: device_auth_tag_hint (string, must match a tag in device_auth), snmptimeout (integer, microseconds, overrides global snmptimeout), snmpretries (integer, overrides global snmpretries), bulkwalk_repeaters (integer, overrides global bulkwalk_repeaters), skip_neighbor_queue (bool, store topology but do not queue new discovers for unknown neighbors). Example: {"device_auth_tag_hint": "site-a", "snmptimeout": 3000000, "skip_neighbor_queue": true}.',
            }
          }
        }
      },
      in => 'body',
    },
  ],
  responses => { default => {} },
}, post '/api/v1/queue/jobs' => require_any_role [qw(api_admin port_control)] => sub {
  my $data = request->body || '';
  my $jobs = (length $data ? try { from_json($data) } : []);

  send_error('Malformed body', 400) if ref $jobs ne ref [];

  foreach my $job (@$jobs) {
      send_error('Malformed job', 400) if ref $job ne ref {};
      send_error('Malformed job', 400) if !defined $job->{action};
      send_error('Not Authorized', 403)
        # TODO make this aware of port control roles per device/port
        if ($job->{action} =~ m/^cf_/ and not user_has_role('port_control'))
        or ($job->{action} !~ m/^cf_/ and not user_has_role('api_admin'));

      if ($job->{device} and not NetAddr::IP::Lite->new($job->{device})) {
          my $ip = ipv4_from_hostname($job->{device})
            or return send_error("Cannot resolve hostname: $job->{device}", 400);
          $job->{device} = $ip;
      }

      $job->{username} = session('logged_in_user');
      $job->{userip}   = request->remote_address;
  }

  my $happy = jq_insert($jobs);

  return send_error('Failed to insert jobs - check backend logs', 500) unless $happy;
  return to_json { success => $happy };
};

true;
