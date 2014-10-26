package App::Netdisco::Web::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

hook 'before_template' => sub {
  my $tokens = shift;

  # new searches will use these defaults in their sidebars
  $tokens->{device_ports} = uri_for('/device/ports');

  # for templates to link to same page with modified query but same options
  my $self_uri = uri_for(request->path, scalar params);
  $self_uri->query_param_delete('q');
  $self_uri->query_param_delete('f');
  $self_uri->query_param_delete('prefer');
  $tokens->{self_options} = $self_uri->query_form_hash;
};

my $handler = sub {
    my $q = param('q');
    my ($tab) = splat;
    my $schema = schema('netdisco')->resultset('Device');

    # we are passed either dns or ip
    my $dev = $schema->search({
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
    my $others = ($schema->search({dns => $first->dns})->count() - 1);

    template 'device', {
      display_name => ($others ? $first->ip : $first->dns),
      tabname => ($tab || 'details'),
    };
};

get '/device'   => require_login $handler;
get '/device/*' => require_login $handler;

true;
