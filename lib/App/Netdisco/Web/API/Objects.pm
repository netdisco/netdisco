package App::Netdisco::Web::API::Objects;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

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

swagger_path {
  tags => ['Objects'],
  path => (setting('api_base') || '').'/object/device/{ip}/jobs',
  description => 'Delete jobs and clear skiplist for a device, optionally filtered by fields',
  parameters  => [
    ip => {
      description => 'Canonical IP of the Device. Use Search methods to find this.',
      required => 1,
      in => 'path',
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
}, del '/api/v1/object/device/:ip/jobs' => require_role api_admin => sub {
  my $device = try { schema(vars->{'tenant'})->resultset('Device')
    ->find( params->{ip} ) } or send_error('Bad Device', 404);

  my $gone = schema(vars->{'tenant'})->resultset('Admin')->search({
    device => param('ip'),
    ( param('port')     ? ( port     => param('port') )     : () ),
    ( param('action')   ? ( action   => param('action') )   : () ),
    ( param('status')   ? ( status   => param('status') )   : () ),
    ( param('username') ? ( username => param('username') ) : () ),
    ( param('userip')   ? ( userip   => param('userip') )   : () ),
    ( param('backend')  ? ( backend  => param('backend') )  : () ),
  })->delete;

  schema(vars->{'tenant'})->resultset('DeviceSkip')->search({
    device => param('ip'),
    ( param('action')  ? ( actionset => { '&&' => \[ 'ARRAY[?]', param('action') ] } ) : () ),
    ( param('backend') ? ( backend   => param('backend') ) : () ),
  })->delete;

  return to_json { deleted => ($gone || 0)};
};

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
  description => "Queue a job to store the nodes found on a given Device",
  parameters  => [
    ip => {
      description => 'Canonical IP of the Device. Use Search methods to find this.',
      required => 1,
      in => 'path',
    },
    nodes => {
      description => 'List of node tuples (port, VLAN, MAC)',
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
}, put '/api/v1/object/device/:ip/nodes' => require_role api_admin => sub {

  jq_insert([{
    action => 'macsuck',
    device => params->{ip},
    subaction => request->body,
    username => session('logged_in_user'),
    userip => request->remote_address,
  }]);

  return to_json {};
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

swagger_path {
  tags => ['Objects'],
  path => (setting('api_base') || '').'/object/device/{ip}/arps',
  description => "Queue a job to store the ARP entries found on a given Device",
  parameters  => [
    ip => {
      description => 'Canonical IP of the Device. Use Search methods to find this.',
      required => 1,
      in => 'path',
    },
    arps => {
      description => 'List of arp tuples (MAC, IP, DNS?). IPs will be resolved to FQDN by Netdisco.',
      default => '[]',
      schema => {
        type => 'array',
        items => {
          type => 'object',
          properties => {
            mac => {
              type => 'string',
              required => 1,
            },
            ip => {
              type => 'string',
              required => 1,
            },
            dns => {
              type => 'string',
              required => 0,
            }
          }
        }
      },
      in => 'body',
    },
  ],
  responses => { default => {} },
}, put '/api/v1/object/device/:ip/arps' => require_role api_admin => sub {

  jq_insert([{
    action => 'arpnip',
    device => params->{ip},
    subaction => request->body,
    username => session('logged_in_user'),
    userip => request->remote_address,
  }]);

  return to_json {};
};

true;
