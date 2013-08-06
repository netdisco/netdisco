package App::Netdisco::Web::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

hook 'before' => sub {
  my @default_port_columns_left = (
    { name => 'c_admin',       label => 'Port Controls',     default => ''   },
    { name => 'c_port',        label => 'Port',              default => 'on' },
  );

  my @default_port_columns_right = (
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
  );

  # build list of port detail columns
  my @port_columns = ();

  push @port_columns,
    grep {$_->{position} eq 'left'} @{ setting('_extra_device_port_cols') };
  push @port_columns, @default_port_columns_left;
  push @port_columns,
    grep {$_->{position} eq 'mid'} @{ setting('_extra_device_port_cols') };
  push @port_columns, @default_port_columns_right;
  push @port_columns,
    grep {$_->{position} eq 'right'} @{ setting('_extra_device_port_cols') };

  var('port_columns' => \@port_columns);

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
      params->{'mac_format'} = 'IEEE';
  }
};

hook 'before_template' => sub {
  my $tokens = shift;

  # new searches will use these defaults in their sidebars
  $tokens->{device_ports} = uri_for('/device', {
    tab => 'ports',
    age_num => 3,
    age_unit => 'months',
    mac_format => 'IEEE',
  });

  # for Net::MAC method
  $tokens->{mac_format_call} = 'as_'. params->{'mac_format'}
    if params->{'mac_format'};

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

get '/device' => require_login sub {
    my $q = param('q');
    my $dev = schema('netdisco')->resultset('Device')->single({
        -or => [
            \[ 'host(me.ip) = ?' => [ bind_value => $q ] ],
            'me.dns' => $q,
        ],
    });

    if (!defined $dev) {
        return redirect uri_for('/', {nosuchdevice => 1})->as_string();
    }

    params->{'tab'} ||= 'details';
    template 'device', { d => $dev };
};

true;
