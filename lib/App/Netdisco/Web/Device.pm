package App::Netdisco::Web::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use URI ();
use URL::Encode 'url_params_mixed';
use App::Netdisco::Util::Device 'match_to_setting';

# build view settings for port connected nodes and devices
set('connected_properties' => [
  sort { $a->{idx} <=> $b->{idx} }
  map  {{ name => $_, %{ setting('sidebar_defaults')->{'device_ports'}->{$_} } }}
  grep { $_ =~ m/^n_/ } keys %{ setting('sidebar_defaults')->{'device_ports'} }
]);

set('port_display_properties' => [
  sort { $a->{idx} <=> $b->{idx} }
  map  {{ name => $_, %{ setting('sidebar_defaults')->{'device_ports'}->{$_} } }}
  grep { $_ =~ m/^p_/ } keys %{ setting('sidebar_defaults')->{'device_ports'} }
]);

hook 'before_template' => sub {
  my $tokens = shift;

  my $defaults = var('sidebar_defaults')->{'device_ports'}
    or return;

  # override ports form defaults with cookie settings
  # always do this so that embedded links to device ports page have user prefs
  if (param('reset')) {
    cookie('nd_ports-form' => '', expires => '-1 day');
  }
  elsif (my $cookie = cookie('nd_ports-form')) {
    my $cdata = url_params_mixed($cookie);

    if ($cdata and (ref {} eq ref $cdata)) {
      foreach my $key (keys %{ $defaults }) {
        $defaults->{$key} = $cdata->{$key};
      }
    }
  }

  # used in the device search sidebar template to set selected items
  foreach my $opt (qw/hgroup lgroup/) {
      my $p = (ref [] eq ref param($opt) ? param($opt)
                                          : (param($opt) ? [param($opt)] : []));
      $tokens->{"${opt}_lkp"} = { map { $_ => 1 } @$p };
  }

  return if param('reset')
    or not var('sidebar_key') or (var('sidebar_key') ne 'device_ports');

  # update cookie from params we just recieved in form submit
  my $uri = URI->new();
  foreach my $key (keys %{ $defaults }) {
    $uri->query_param($key => param($key));
  }
  cookie('nd_ports-form' => $uri->query(), expires => '365 days');
};

get '/device' => require_login sub {
    my $q = param('q');
    my $devices = schema(vars->{'tenant'})->resultset('Device');

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

    # load and cache device port control configuration
    # convert LHS device ACLs to named groups
    my $user = logged_in_user;
    if ($user->portctl_role) {
        my $role = $user->portctl_role;
        my $rows = schema(vars->{'tenant'})->resultset('PortCtlRole')
          ->search({ role_name => $role },
                   { prefetch => [qw/device_acl port_acl/], order_by => 'me.id' });
        while (my $pair = $rows->next) {
            my $group = 'synthesized_group_'. $pair->device_acl->id;
            config->{host_groups}->{$group} = $pair->device_acl->rules;
            config->{portctl_by_role}->{$role}->{'group:'. $group}
              = $pair->port_acl->rules;
        }
    }

    params->{'tab'} ||= 'details';
    template 'device', {
      netdisco_device => $first,
      display_name => ($others ? $first->ip : ($first->dns || $first->ip)),
      device_count => schema(vars->{'tenant'})->resultset('Device')->count(),
      lgroup_list => [ schema(vars->{'tenant'})->resultset('Device')->get_distinct_col('location') ],
      hgroup_list => setting('host_group_displaynames'),
      device => params->{'tab'},
    }, { layout => 'main' };
};

true;
