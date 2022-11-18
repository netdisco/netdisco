package App::Netdisco::Web::API::Objects;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Backend::Job;
use App::Netdisco::JobQueue 'jq_insert';

use Try::Tiny;

swagger_path {
  tags => ['Objects'],
  path => (setting('api_base') || '').'/object/device/{ip}',
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
  my $device = try { schema(vars->{'tenant'})->resultset('Device')
    ->find( params->{ip} ) } or send_error('Bad Device', 404);
  return to_json $device->TO_JSON;
};

foreach my $rel (qw/device_ips vlans ports modules port_vlans wireless_ports ssids powered_ports/) {
    swagger_path {
      tags => ['Objects'],
      path => (setting('api_base') || '')."/object/device/{ip}/$rel",
      description => "Returns $rel rows for a given device",
      parameters  => [
        ip => {
          description => 'Canonical IP of the Device. Use Search methods to find this.',
          required => 1,
          in => 'path',
        },
      ],
      responses => { default => {} },
    }, get "/api/v1/object/device/:ip/$rel" => require_role api => sub {
      my $rows = try { schema(vars->{'tenant'})->resultset('Device')
        ->find( params->{ip} )->$rel } or send_error('Bad Device', 404);
      return to_json [ map {$_->TO_JSON} $rows->all ];
    };
}

foreach my $rel (qw/nodes active_nodes nodes_with_age active_nodes_with_age vlans logs/) {
    swagger_path {
      tags => ['Objects'],
      description => "Returns $rel rows for a given port",
      path => (setting('api_base') || '')."/object/device/{ip}/port/{port}/$rel",
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
    }, get qr{/api/v1/object/device/(?<ip>[^/]+)/port/(?<port>.+)/${rel}$} => require_role api => sub {
      my $params = captures;
      my $rows = try { schema(vars->{'tenant'})->resultset('DevicePort')
        ->find( $$params{port}, $$params{ip} )->$rel }
        or send_error('Bad Device or Port', 404);
      return to_json [ map {$_->TO_JSON} $rows->all ];
    };
}

foreach my $rel (qw/power properties ssid wireless agg_master neighbor last_node/) {
    swagger_path {
      tags => ['Objects'],
      description => "Returns the related $rel table entry for a given port",
      path => (setting('api_base') || '')."/object/device/{ip}/port/{port}/$rel",
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
    }, get qr{/api/v1/object/device/(?<ip>[^/]+)/port/(?<port>.+)/${rel}$} => require_role api => sub {
      my $params = captures;
      my $row = try { schema(vars->{'tenant'})->resultset('DevicePort')
        ->find( $$params{port}, $$params{ip} )->$rel }
        or send_error('Bad Device or Port', 404);
      return to_json $row->TO_JSON;
    };
}

# must come after the port methods above, so the route matches later
swagger_path {
  tags => ['Objects'],
  description => 'Returns a row from the device_port table',
  path => (setting('api_base') || '').'/object/device/{ip}/port/{port}',
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
}, get qr{/api/v1/object/device/(?<ip>[^/]+)/port/(?<port>.+)$} => require_role api => sub {
  my $params = captures;
  my $port = try { schema(vars->{'tenant'})->resultset('DevicePort')
    ->find( $$params{port}, $$params{ip} ) }
    or send_error('Bad Device or Port', 404);
  return to_json $port->TO_JSON;
};

swagger_path {
  tags => ['Objects'],
  path => (setting('api_base') || '').'/object/device/{ip}/nodes',
  description => "Returns the nodes found on a given Device",
  parameters  => [
    ip => {
      description => 'Canonical IP of the Device. Use Search methods to find this.',
      required => 1,
      in => 'path',
    },
    active_only => {
      description => 'Restrict results to active Nodes only',
      type => 'boolean',
      default => 'true',
      in => 'query',
    },
  ],
  responses => { default => {} },
}, get '/api/v1/object/device/:ip/nodes' => require_role api => sub {
  my $active = (params->{active_only} and ('true' eq params->{active_only})) ? 1 : 0;
  my $rows = try { schema(vars->{'tenant'})->resultset('Node')
    ->search({ switch => params->{ip}, ($active ? (-bool => 'active') : ()) }) }
    or send_error('Bad Device', 404);
  return to_json [ map {$_->TO_JSON} $rows->all ];
};

swagger_path {
  tags => ['Objects'],
  path => (setting('api_base') || '').'/object/device/{ip}/nodes',
  description => "Stores the nodes found on a given Device",
  parameters  => [
    ip => {
      description => 'Canonical IP of the Device. Use Search methods to find this.',
      required => 1,
      in => 'path',
    },
    enqueue => {
      description => 'Import nodes as a backend job, not right now',
      type => 'boolean',
      default => 'false',
      in => 'query',
    },
    nodes => {
      description => 'List of node tuples (port, vlan, mac)',
      default => '[]',
      schema => {
        type => 'array',
        items => {
          type => 'object',
          properties => {
            port => {
              type => 'string'
            },
            vlan => {
              type => 'integer',
              default => '1'
            },
            mac => {
              type => 'string'
            }
          }
        }
      },
      in => 'body',
    },
  ],
  responses => { default => {} },
}, put '/api/v1/object/device/:ip/nodes' => require_role api => sub {
  my $enqueue = (params->{enqueue} and ('true' eq params->{enqueue})) ? 1 : 0;
  my $body = request->body;
  my $action = 'macsuck';
  my $job_spec = {
    action => $action,
    device => params->{ip},
    subaction => $body,
    username => request->user,
  };
  my $exitstatus = 0;

  if ($enqueue) {
      jq_insert([ $job_spec ]);
  }
  else {
      # create worker (placeholder object for the action runner)
      {
        package MyWorker;
        use Moo;
        with 'App::Netdisco::Worker::Runner';
      }

      my $worker = MyWorker->new();
      my $job = App::Netdisco::Backend::Job->new({ job => 0, %$job_spec });

      # do job
      try {
        $worker->run($job);
      }
      catch {
        $job->status('error');
        $job->log("error running job: $_");
      };
      debug sprintf '%s: finished at %s', $action, scalar localtime;
      debug sprintf '%s: status %s: %s', $action, $job->status, $job->log;
      $exitstatus = 1 if !$exitstatus and $job->status ne 'done';
  }

  return to_json [];
};

swagger_path {
  tags => ['Objects'],
  path => (setting('api_base') || '').'/object/vlan/{vlan}/nodes',
  description => "Returns the nodes found in a given VLAN",
  parameters  => [
    vlan => {
      description => 'VLAN number',
      type => 'integer',
      required => 1,
      in => 'path',
    },
    active_only => {
      description => 'Restrict results to active Nodes only',
      type => 'boolean',
      default => 'true',
      in => 'query',
    },
  ],
  responses => { default => {} },
}, get '/api/v1/object/vlan/:vlan/nodes' => require_role api => sub {
  my $active = (params->{active_only} and ('true' eq params->{active_only})) ? 1 : 0;
  my $rows = try { schema(vars->{'tenant'})->resultset('Node')
    ->search({ vlan => params->{vlan}, ($active ? (-bool => 'active') : ()) }) }
    or send_error('Bad VLAN', 404);
  return to_json [ map {$_->TO_JSON} $rows->all ];
};

true;
