package App::Netdisco::Web::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use URL::Encode 'url_params_mixed';

hook 'before' => sub {

  # build list of port detail columns
  my @port_columns =
    sort { $a->{idx} <=> $b->{idx} }
    map  {{ name => $_, %{ setting('sidebar_defaults')->{'device_ports'}->{$_} } }}
    grep { $_ =~ m/^c_/ } keys %{ setting('sidebar_defaults')->{'device_ports'} };

  splice @port_columns, setting('device_port_col_idx_left'), 0,
    grep {$_->{position} eq 'left'}  @{ setting('_extra_device_port_cols') };
  splice @port_columns, setting('device_port_col_idx_mid'), 0,
    grep {$_->{position} eq 'mid'}   @{ setting('_extra_device_port_cols') };
  splice @port_columns, setting('device_port_col_idx_right'), 0,
    grep {$_->{position} eq 'right'} @{ setting('_extra_device_port_cols') };

  var('port_columns' => \@port_columns);

  # need to update sidebar_defaults so code scanning params sees plugin cols
  setting('sidebar_defaults')->{'device_ports'}->{ $_->{name} } = $_
    for @port_columns;

  # build view settings for port connected nodes and devices
  var('connected_properties' => [
    sort { $a->{idx} <=> $b->{idx} }
    map  {{ name => $_, %{ setting('sidebar_defaults')->{'device_ports'}->{$_} } }}
    grep { $_ =~ m/^n_/ } keys %{ setting('sidebar_defaults')->{'device_ports'} }
  ]);

  return unless (request->path eq uri_for('/device')->path
    or index(request->path, uri_for('/ajax/content/device')->path) == 0);

  # override ports form defaults with cookie settings
  if (param('reset')) {
    cookie('nd_ports-form' => '', expires => '-1 day');
  }
  elsif (my $cookie = cookie('nd_ports-form')) {
    my $cdata = url_params_mixed($cookie);

    if ($cdata and (ref {} eq ref $cdata)) {
      foreach my $key (keys %{ setting('sidebar_defaults')->{'device_ports'} }) {
        next unless defined $cdata->{$key}
          and $cdata->{$key} =~ m/^[[:alnum:]_]+$/;
        setting('sidebar_defaults')->{'device_ports'}->{$key}->{'default'}
          = $cdata->{$key};
      }
    }
  }

  params->{'firstsearch'} = 'on';
# TODO set cookie
#  if (param('reset') or not param('tab') or param('tab') ne 'ports') {
};

get '/device' => require_login sub {
    my $q = param('q');
    my $devices = schema('netdisco')->resultset('Device');

    # we are passed either dns or ip
    my $dev = $devices->search({
        -or => [
            \[ 'host(me.ip) = ?' => [ bind_value => $q ] ],
            'me.dns' => $q,
        ],
    });

    if ($dev->count == 0) {
        return redirect uri_for('/', {nosuchdevice => 1, device => $q})->path_query;
    }

    # if passed dns, need to check for duplicates
    # and use only ip for q param, if there are duplicates.
    my $first = $dev->first;
    my $others = ($devices->search({dns => $first->dns})->count() - 1);

    params->{'tab'} ||= 'details';
    template 'device', {
      display_name => ($others ? $first->ip : ($first->dns || $first->ip)),
      device => params->{'tab'},
    };
};

true;
