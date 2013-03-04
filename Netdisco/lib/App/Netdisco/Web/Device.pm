package App::Netdisco::Web::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

hook 'before' => sub {
  # list of port detail columns
  var('port_columns' => [
    { name => 'c_admin',       label => 'Admin Controls',    default => ''   },
    { name => 'c_port',        label => 'Port',              default => 'on' },
    { name => 'c_descr',       label => 'Description',       default => ''   },
    { name => 'c_type',        label => 'Type',              default => ''   },
    { name => 'c_duplex',      label => 'Duplex',            default => ''   },
    { name => 'c_lastchange',  label => 'Last Change',       default => ''   },
    { name => 'c_name',        label => 'Name',              default => 'on' },
    { name => 'c_speed',       label => 'Speed',             default => ''   },
    { name => 'c_mac',         label => 'Port MAC',          default => ''   },
    { name => 'c_mtu',         label => 'MTU',               default => ''   },
    { name => 'c_vlan',        label => 'Native VLAN',       default => 'on' },
    { name => 'c_vmember',     label => 'Tagged VLANs',      default => 'on' },
    { name => 'c_power',       label => 'PoE',               default => ''   },
    { name => 'c_nodes',       label => 'Connected Nodes',   default => ''   },
    { name => 'c_neighbors',   label => 'Connected Devices', default => 'on' },
    { name => 'c_stp',         label => 'Spanning Tree',     default => ''   },
    { name => 'c_up',          label => 'Status',            default => ''   },
  ]);

  # view settings for port connected devices
  var('connected_properties' => [
    { name => 'n_age',      label => 'Age Stamp',     default => ''   },
    { name => 'n_ip',       label => 'IP Address',    default => 'on' },
    { name => 'n_archived', label => 'Archived Data', default => ''   },
  ]);

  return unless (request->path eq uri_for('/device')->path
    or index(request->path, uri_for('/ajax/content/device')->path) == 0);

  foreach my $col (@{ var('port_columns') }) {
      next unless $col->{default} eq 'on';
      params->{$col->{name}} = 'checked'
        if not param('tab') or param('tab') ne 'ports';
  }

  foreach my $col (@{ var('connected_properties') }) {
      next unless $col->{default} eq 'on';
      params->{$col->{name}} = 'checked'
        if not param('tab') or param('tab') ne 'ports';
  }

  if (not param('tab') or param('tab') ne 'ports') {
      params->{'age_num'} = 3;
      params->{'age_unit'} = 'months';
  }
};

hook 'before_template' => sub {
  my $tokens = shift;

  # new searches will use these defaults in their sidebars
  $tokens->{device_ports} = uri_for('/device', {
    tab => 'ports',
    age_num => 3,
    age_unit => 'months',
  });

  foreach my $col (@{ var('port_columns') }) {
      next unless $col->{default} eq 'on';
      $tokens->{device_ports}->query_param($col->{name}, 'checked');
  }

  foreach my $col (@{ var('connected_properties') }) {
      next unless $col->{default} eq 'on';
      $tokens->{device_ports}->query_param($col->{name}, 'checked');
  }

  return unless (request->path eq uri_for('/device')->path
    or index(request->path, uri_for('/ajax/content/device')->path) == 0);

  # for templates to link to same page with modified query but same options
  my $self_uri = uri_for(request->path, scalar params);
  $self_uri->query_param_delete('q');
  $self_uri->query_param_delete('f');
  $tokens->{self_options} = $self_uri->query_form_hash;
};

get '/device' => sub {
    my $q = param('q');
    my $dev = schema('netdisco')->resultset('Device')->single({
        -or => [
            \[ 'host(me.ip) = ?' => [ bind_value => $q ] ],
            'me.dns' => $q,
        ],
    });

    if (!defined $dev) {
        status(302);
        header(Location => uri_for('/', {nosuchdevice => 1})->path_query());
        return;
    }

    params->{'tab'} ||= 'details';
    template 'device', { d => $dev };
};

true;
