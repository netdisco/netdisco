package App::Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;

use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Swagger;

use Dancer::Error;
use Dancer::Continuation::Route::ErrorSent;

use URI ();
use Socket6 (); # to ensure dependency is met
use HTML::Entities (); # to ensure dependency is met
use URI::QueryParam (); # part of URI, to add helper methods
use MIME::Base64 'encode_base64';
use Path::Class 'dir';
use Module::Load ();
use Data::Visitor::Tiny;
use Scalar::Util 'blessed';
use Storable 'dclone';
use URI::Based;

use App::Netdisco::Util::Web qw/
  interval_to_daterange
  request_is_api
  request_is_api_report
  request_is_api_search
/;
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;

BEGIN {
  no warnings 'redefine';

  # https://github.com/PerlDancer/Dancer/issues/967
  *Dancer::_redirect = sub {
      my ($destination, $status) = @_;
      my $response = Dancer::SharedData->response;
      $response->status($status || 302);
      $response->headers('Location' => $destination);
  };

  # neater than using Dancer::Plugin::Res to handle JSON differently
  *Dancer::send_error = sub {
      my ($body, $status) = @_;
      if (request_is_api) {
        status $status || 400;
        $body = '' unless defined $body;
        Dancer::Continuation::Route::ErrorSent->new(
            return_value => to_json { error => $body, return_url => param('return_url') }
        )->throw;
      }
      Dancer::Continuation::Route::ErrorSent->new(
          return_value => Dancer::Error->new(
              message => $body,
              code => $status || 500)->render()
      )->throw;
  };

  # to insert /t/$tenant if set
  # which is fine for building links, but not fine for
  # comparison to request->path, because when is_forward() the
  # request->path is changed...
  *Dancer::Request::uri_for = sub {
    my ($self, $part, $params, $dont_escape) = @_;
    my $uri = $self->base;

    if (vars->{'tenant'}) {
        $part = '/t/'. vars->{'tenant'} . $part;
    }

    # Make sure there's exactly one slash between the base and the new part
    my $base = $uri->path;
    $base =~ s|/$||;
    $part =~ s|^/||;
    $uri->path("$base/$part");

    $uri->query_form($params) if $params;

    return $dont_escape ? uri_unescape($uri->canonical) : $uri->canonical;
  };

  # ...so here we are monkeypatching request->path as well
  *Dancer::Request::path = sub {
    die "path is accessor not mutator" if scalar @_ > 1;
    my $self = shift;
    $self->_build_path() unless $self->{path};

    if (vars->{'tenant'} and $self->{path} !~ m{/t/}) {
        my $path = $self->{path};
        my $base = setting('path');
        my $tenant = '/t/' . vars->{'tenant'};

        $tenant = ($base . $tenant) if $base ne '/';
        $tenant .= '/' if $base eq '/';
        $path =~ s/^$base/$tenant/;

        return $path;
    }
    return $self->{path};
  };

  # implement same_site
  # from https://github.com/PerlDancer/Dancer-Session-Cookie/issues/20
  *Dancer::Session::Cookie::_cookie_params = sub {
      my $self     = shift;
      my $name     = $self->session_name;
      my $duration = $self->_session_expires_as_duration;
      my %cookie   = (
          name      => $name,
          value     => $self->_cookie_value,
          path      => setting('session_cookie_path') || '/',
          domain    => setting('session_domain'),
          secure    => setting('session_secure'),
          http_only => setting("session_is_http_only") // 1,
          same_site => setting("session_same_site"),
      );
      if ( defined $duration ) {
          $cookie{expires} = time + $duration;
      }
      return %cookie;
  };
}

use App::Netdisco::Web::AuthN;
use App::Netdisco::Web::Static;
use App::Netdisco::Web::Search;
use App::Netdisco::Web::Device;
use App::Netdisco::Web::Report;
use App::Netdisco::Web::API::Objects;
use App::Netdisco::Web::API::Queue;
use App::Netdisco::Web::AdminTask;
use App::Netdisco::Web::TypeAhead;
use App::Netdisco::Web::PortControl;
use App::Netdisco::Web::Statistics;
use App::Netdisco::Web::Password;
use App::Netdisco::Web::CustomFields;
use App::Netdisco::Web::GenericReport;

sub _load_web_plugins {
  my $plugin_list = shift;

  foreach my $plugin (@$plugin_list) {
      $plugin =~ s/^X::/+App::NetdiscoX::Web::Plugin::/;
      $plugin = 'App::Netdisco::Web::Plugin::'. $plugin
        if $plugin !~ m/^\+/;
      $plugin =~ s/^\+//;

      $ENV{ND2_LOG_PLUGINS} && debug "loading web plugin $plugin";
      Module::Load::load $plugin;
  }
}

if (setting('web_plugins') and ref [] eq ref setting('web_plugins')) {
    _load_web_plugins( setting('web_plugins') );
}

if (setting('extra_web_plugins') and ref [] eq ref setting('extra_web_plugins')) {
    unshift @INC, dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'site_plugins')->stringify;
    _load_web_plugins( setting('extra_web_plugins') );
}

foreach my $tag (keys %{ setting('_admin_tasks') }) {
    my $code = sub {
        # trick the ajax into working as if this were a tabbed page
        params->{tab} = $tag;

        var(nav => 'admin');
        template 'admintask', {
          task => setting('_admin_tasks')->{ $tag },
        }, { layout => 'main' };
    };

    if (setting('_admin_tasks')->{ $tag }->{ 'roles' }) {
        get "/admin/$tag" => require_any_role setting('_admin_tasks')->{ $tag }->{ 'roles' } => $code;
    }
    else {
        get "/admin/$tag" => require_role admin => $code;
    }
}


# after plugins are loaded, add our own template path
push @{ config->{engines}->{netdisco_template_toolkit}->{INCLUDE_PATH} },
     setting('views');

# sort the reports which have been loaded, by their label
foreach my $cat (@{ setting('_report_order') }) {
    setting('_reports_menu')->{ $cat } ||= [];
    setting('_reports_menu')->{ $cat }
      = [ sort { setting('_reports')->{$a}->{'label'}
                 cmp
                 setting('_reports')->{$b}->{'label'} }
          @{ setting('_reports_menu')->{ $cat } } ];
}

# any template paths in deployment.yml (should override plugins)
if (setting('template_paths') and ref [] eq ref setting('template_paths')) {
    if (setting('site_local_files')) {
      push @{setting('template_paths')},
         dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'nd-site-local', 'share')->stringify,
         dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'nd-site-local', 'share', 'views')->stringify;
    }
    unshift @{ config->{engines}->{netdisco_template_toolkit}->{INCLUDE_PATH} },
      @{setting('template_paths')};
}

# load cookie key from database
setting('session_cookie_key' => undef);
setting('session_cookie_key' => 'this_is_for_testing_only')
  if $ENV{HARNESS_ACTIVE};
eval {
  my $sessions = schema('netdisco')->resultset('Session');
  my $skey = $sessions->find({id => 'dancer_session_cookie_key'});
  setting('session_cookie_key' => $skey->get_column('a_session')) if $skey;
};
Dancer::Session::Cookie::init(session);

# workaround for https://github.com/PerlDancer/Dancer/issues/935
hook after_error_render => sub { setting('layout' => 'main') };

# build list of port detail columns
{
  my @port_columns =
    sort { $a->{idx} <=> $b->{idx} }
    map  {{ name => $_, %{ setting('sidebar_defaults')->{'device_ports'}->{$_} } }}
    grep { $_ =~ m/^c_/ } keys %{ setting('sidebar_defaults')->{'device_ports'} };

  splice @port_columns, setting('device_port_col_idx_right') + 1, 0,
    grep {$_->{position} eq 'right'} @{ setting('_extra_device_port_cols') };
  splice @port_columns, setting('device_port_col_idx_mid') + 1, 0,
    grep {$_->{position} eq 'mid'}   @{ setting('_extra_device_port_cols') };
  splice @port_columns, setting('device_port_col_idx_left') + 1, 0,
    grep {$_->{position} eq 'left'}  @{ setting('_extra_device_port_cols') };

  set('port_columns' => \@port_columns);

  # update sidebar_defaults so hooks scanning params see new plugin cols
  setting('sidebar_defaults')->{'device_ports'}->{ $_->{name} } = $_
    for @port_columns;
}

# build lookup for tenancies
{
    set('tenant_data' => {
        map { ( $_->{tag} => { displayname => $_->{'displayname'},
                               tag => $_->{'tag'},
                               path => config->{'url_base'}->with("/t/$_->{tag}")->path } ) }
            @{ setting('tenant_databases') },
            { tag => 'netdisco', displayname => (setting('database')->{displayname} || 'Default') }
    });
    config->{'tenant_data'}->{'netdisco'}->{'path'}
      = URI::Based->new((config->{path} eq '/') ? '' : config->{path})->path;
    set('tenant_tags' => [  map { $_->{'tag'} }
                           sort { $a->{'displayname'} cmp $b->{'displayname'} }
                                values %{ config->{'tenant_data'} } ]);
}

hook 'before' => sub {
  my $key = request->path;
  if (param('tab') and ($key !~ m/ajax/)) {
      $key .= ('/' . param('tab'));
  }
  $key =~ s|.*/(\w+)/(\w+)$|${1}_${2}|;
  var(sidebar_key => $key);

  # trim whitespace
  params->{'q'} =~ s/^\s+|\s+$//g if param('q');

  # copy sidebar defaults into vars so we can mess about with it
  foreach my $sidebar (keys %{setting('sidebar_defaults')}) {
    vars->{'sidebar_defaults'}->{$sidebar} = { map {
      ($_ => setting('sidebar_defaults')->{$sidebar}->{$_}->{'default'})
    } keys %{setting('sidebar_defaults')->{$sidebar}} };
  }
};

# swagger submits "false" params whereas web UI does not - remove them
# so that code testing for param existence as truth still works.
hook 'before' => sub {
  return unless request_is_api_report or request_is_api_search;
  map {delete params->{$_} if params->{$_} eq 'false'} keys %{params()};
};

hook 'before_template' => sub {
  # search or report from navbar, or reset of sidebar, can ignore params
  return if param('firstsearch')
    or var('sidebar_key') !~ m/^\w+_\w+$/;

  # update defaults to contain the passed url params
  # (this follows initial copy from config.yml, then cookie restore)
  var('sidebar_defaults')->{var('sidebar_key')}->{$_} = param($_)
    for keys %{ var('sidebar_defaults')->{var('sidebar_key')} || {} };
};

hook 'before_template' => sub {
    my $tokens = shift;

    # quick b64 encode
    $tokens->{atob} = sub { encode_base64(shift, '') };

    # allow portable static content
    $tokens->{uri_base} = request->base->path
      if request->base->path ne '/';
    $tokens->{uri_base} .= ('/t/'. vars->{'tenant'})
      if vars->{'tenant'};

    # allow portable dynamic content
    $tokens->{uri_for} = sub { uri_for(@_)->path_query };

    # current query string to all resubmit from within ajax template
    my $queryuri = URI->new();
    $queryuri->query_param($_ => param($_))
      for grep {$_ ne 'return_url'} keys %{params()};
    $tokens->{my_query} = $queryuri->query();

    # hide custom fields according to only/no settings
    $tokens->{permitted_by_acl} = sub {
        my ($thing, $config) = @_;
        return false unless $thing and $config;

        return if acl_matches($thing, ($config->{no} || []));
        return unless acl_matches_only($thing, ($config->{only} || []));
        return true;
    };

    # access to logged in user's roles (modulo RBAC)
    # role will be "admin" "port_control" "radius" or "ldap"
    $tokens->{user_has_role} = sub {
        my ($role, $device) = @_;
        return false unless $role;

        return user_has_role($role) if $role ne 'port_control';
        return false unless user_has_role('port_control');
        return true if not $device;

        my $user = logged_in_user or return false;
        return true unless $user->portctl_role;

        # this has the merged yaml and database config
        my $acl = setting('portctl_by_role')->{$user->portctl_role};
        if ($acl and (ref $acl eq q{} or ref $acl eq ref [])) {
            return true if acl_matches($device, $acl);
        }
        elsif ($acl and ref $acl eq ref {}) {
            foreach my $key (grep { defined } sort keys %$acl) {
                # lhs matches device, rhs matches port
                # but we are not interested in the ports
                return true if acl_matches($device, $key);
            }
        }

        # assigned an unknown role
        return false;
    };

    # create date ranges from within templates
    $tokens->{to_daterange}  = sub { interval_to_daterange(@_) };

    # data structure for DataTables records per page menu
    $tokens->{table_showrecordsmenu} =
      to_json( setting('table_showrecordsmenu') );

    # linked searches will use these default url path params
    foreach my $sidebar_key (keys %{ var('sidebar_defaults') }) {
        my ($mode, $report) = ($sidebar_key =~ m/(\w+)_(\w+)/);
        if ($mode =~ m/^(?:search|device)$/) {
            $tokens->{$sidebar_key} = uri_for("/$mode", {tab => $report});
        }
        elsif ($mode =~ m/^report$/) {
            $tokens->{$sidebar_key} = uri_for("/$mode/$report");
        }

        foreach my $col (keys %{ var('sidebar_defaults')->{$sidebar_key} }) {
            $tokens->{$sidebar_key}->query_param($col,
              var('sidebar_defaults')->{$sidebar_key}->{$col});
        }

        # fix Plugin Template Variables to be only path+query
        $tokens->{$sidebar_key} = $tokens->{$sidebar_key}->path_query;
    }

    # helper from NetAddr::MAC for the MAC formatting
    $tokens->{mac_format_call} = 'as_'. lc(param('mac_format'))
      if param('mac_format');

    # allow very long lists of ports
    $Template::Directive::WHILE_MAX = 10_000;

    # allow hash keys with leading underscores
    $Template::Stash::PRIVATE = undef;
};

# prevent Template::AutoFilter taking action on CSV output
hook 'before_template' => sub {
    my $template_engine = engine 'template';
    if (not request->is_ajax
        and header('Content-Type')
        and header('Content-Type') eq 'text/comma-separated-values' ) {

        $template_engine->{config}->{AUTO_FILTER} = 'none';
        $template_engine->init();
    }
    # debug $template_engine->{config}->{AUTO_FILTER};
};
hook 'after_template_render' => sub {
    my $template_engine = engine 'template';
    if (not request->is_ajax
        and header('Content-Type')
        and header('Content-Type') eq 'text/comma-separated-values' ) {

        $template_engine->{config}->{AUTO_FILTER} = 'html_entity';
        $template_engine->init();
    }
    # debug $template_engine->{config}->{AUTO_FILTER};
};

# support for report api which is basic table result in json
hook before_layout_render => sub {
  my ($tokens, $html_ref) = @_;
  return unless request_is_api_report or request_is_api_search;

  if (ref {} eq ref $tokens and exists $tokens->{results}) {
      ${ $html_ref } = to_json $tokens->{results};
  }
  elsif (ref {} eq ref $tokens) {
      map {delete $tokens->{$_}}
           grep {not blessed $tokens->{$_} or not $tokens->{$_}->isa('App::Netdisco::DB::ResultSet')}
                keys %$tokens;

      visit( $tokens, sub {
          my ( $key, $valueref ) = @_;
          $$valueref = [$$valueref->hri->all]
            if blessed $$valueref and $$valueref->isa('App::Netdisco::DB::ResultSet');
      });

      ${ $html_ref } = to_json $tokens;
  }
  else {
      ${ $html_ref } = '[]';
  }
};

# workaround for Swagger plugin weird response body
hook 'after' => sub {
    my $r = shift; # a Dancer::Response

    if (request->path =~ m{/swagger\.json} and
        request->path eq uri_for('/swagger.json')->path
          and ref {} eq ref $r->content) {
        my $spec = dclone $r->content;

        if (vars->{'tenant'}) {
            my $base = setting('path');
            my $tenant = '/t/' . vars->{'tenant'};
            $tenant = ($base . $tenant) if $base ne '/';
            $tenant .= '/' if $base eq '/';

            foreach my $path (sort keys %{ $spec->{paths} }) {
                (my $newpath = $path) =~ s/^$base/$tenant/;
                $spec->{paths}->{$newpath} = delete $spec->{paths}->{$path};
            }
        }

        $r->content( to_json( $spec ) );
        header('Content-Type' => 'application/json');
    }

    # instead of setting serialiser
    # and also to handle some plugins just returning undef if search fails
    if (request_is_api) {
        header('Content-Type' => 'application/json');
        $r->content( $r->content || '[]' );
    }
};

# setup for swagger API
my $swagger = Dancer::Plugin::Swagger->instance;
my $swagger_doc = $swagger->doc;

$swagger_doc->{consumes} = 'application/json';
$swagger_doc->{produces} = 'application/json';
$swagger_doc->{tags} = [
  {name => 'General',
    description => 'Log in and Log out'},
  {name => 'Search',
    description => 'Search Operations'},
  {name => 'Objects',
    description => 'Device, Port, and associated Node Data'},
  {name => 'Reports',
    description => 'Canned and Custom Reports'},
  {name => 'Queue',
    description => 'Operations on the Job Queue'},
];

$swagger_doc->{securityDefinitions} = {
  APIKeyHeader =>
    { type => 'apiKey', name => 'Authorization', in => 'header' },
  BasicAuth =>
    { type => 'basic'  },
};
$swagger_doc->{security} = [ { APIKeyHeader => [] } ];

if (setting('trust_x_remote_user')) {
    foreach my $path (keys %{ $swagger_doc->{paths} }) {
        foreach my $method (keys %{ $swagger_doc->{paths}->{$path} }) {
            unshift @{ $swagger_doc->{paths}->{$path}->{$method}->{parameters} }, {
              name => 'X-REMOTE_USER',
              description => 'API client user name',
              in => 'header',
              required => false,
              type => 'string',
            };
        }
    }
}

# manually install Swagger UI routes because plugin doesn't handle non-root
# hosting, so we cannot use show_ui(1)
my $swagger_base = config->{plugins}->{Swagger}->{ui_url};

get $swagger_base => sub {
    Dancer::Plugin::Swagger->instance->doc->{schemes} = [ request->scheme ];
    redirect uri_for($swagger_base)->path
      . '/?url=' . uri_for('/swagger.json')->path;
};

get $swagger_base.'/' => sub {
    Dancer::Plugin::Swagger->instance->doc->{schemes} = [ request->scheme ];
    # user might request /swagger-ui/ initially (Plugin doesn't handle this)
    params->{url} or redirect uri_for($swagger_base)->path;
    send_file( 'swagger-ui/index.html' );
};

# omg the plugin uses system_path and we don't want to go there
get $swagger_base.'/**' => sub {
    Dancer::Plugin::Swagger->instance->doc->{schemes} = [ request->scheme ];
    send_file( join '/', 'swagger-ui', @{ (splat())[0] } );
};

# remove empty lines from CSV response
# this makes writing templates much more straightforward!
hook 'after' => sub {
    my $r = shift; # a Dancer::Response

    if ($r->content_type and $r->content_type eq 'text/comma-separated-values') {
        my @newlines = ();
        my @lines = split m/\n/, $r->content;

        foreach my $line (@lines) {
            push @newlines, $line if $line !~ m/^\s*$/;
        }

        $r->content(join "\n", @newlines);
    }
};

# support for tenancies
any qr{^/t/(?<tenant>[^/]+)/?$} => sub {
    my $capture = captures;
    var tenant => $capture->{'tenant'};
    forward '/';
};
any '/t/*/**' => sub {
    my ($tenant, $path) = splat;
    var tenant => $tenant;
    forward (join '/', '', @$path, (request->path =~ m{/$} ? '' : ()));
};

any qr{.*} => sub {
    var('notfound' => true);
    status 'not_found';
    template 'index', {}, { layout => 'main' };
};

true;
