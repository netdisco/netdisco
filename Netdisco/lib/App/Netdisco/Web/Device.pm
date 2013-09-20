package App::Netdisco::Web::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use URL::Encode 'url_params_mixed';

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

  # override ports form defaults with cookie settings

  my $cookie = cookie('nd_ports-form');
  my $cdata = url_params_mixed($cookie);

  if ($cdata and ref {} eq ref $cdata and not param('reset')) {
      foreach my $item (@{ var('port_columns') }) {
          my $key = $item->{name};
          next unless defined $cdata->{$key}
            and $cdata->{$key} =~ m/^[[:alnum:]_]+$/;
          $item->{default} = $cdata->{$key};
      }

      foreach my $item (@{ var('connected_properties') }) {
          my $key = $item->{name};
          next unless defined $cdata->{$key}
            and $cdata->{$key} =~ m/^[[:alnum:]_]+$/;
          $item->{default} = $cdata->{$key};
      }

      foreach my $key (qw/age_num age_unit mac_format/) {
          params->{$key} ||= $cdata->{$key}
            if defined $cdata->{$key}
               and $cdata->{$key} =~ m/^[[:alnum:]_]+$/;
      }
  }

  # copy ports form defaults into request query params if this is
  # a redirect from within the application (tab param is not set)

  if (param('reset') or not param('tab') or param('tab') ne 'ports') {
      foreach my $col (@{ var('port_columns') }) {
          delete params->{$col->{name}};
          params->{$col->{name}} = 'checked'
            if $col->{default} eq 'on';
      }

      foreach my $col (@{ var('connected_properties') }) {
          delete params->{$col->{name}};
          params->{$col->{name}} = 'checked'
            if $col->{default} eq 'on';
      }

      # not stored in the cookie
      params->{'age_num'} ||= 3;
      params->{'age_unit'} ||= 'months';
      params->{'mac_format'} ||= 'IEEE';

      if (param('reset')) {
          params->{'age_num'} = 3;
          params->{'age_unit'} = 'months';
          params->{'mac_format'} = 'IEEE';

          # nuke the port params cookie
          cookie('nd_ports-form' => '', expires => '-1 day');
      }
  }
};

hook 'before_template' => sub {
  my $tokens = shift;

  # new searches will use these defaults in their sidebars
  $tokens->{device_ports} = uri_for('/device', { tab => 'ports' });

  # copy ports form defaults into helper values for building template links

  foreach my $key (qw/age_num age_unit mac_format/) {
      $tokens->{device_ports}->query_param($key, params->{$key});
  }

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
    template 'device', {
      d => $dev,
      device => params->{'tab'},
    };
};

true;
