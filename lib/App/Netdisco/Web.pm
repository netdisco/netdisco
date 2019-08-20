package App::Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;

use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Swagger;

use URI ();
use Socket6 (); # to ensure dependency is met
use HTML::Entities (); # to ensure dependency is met
use URI::QueryParam (); # part of URI, to add helper methods
use Path::Class 'dir';
use Module::Load ();
use App::Netdisco::Util::Web 'interval_to_daterange';

use App::Netdisco::Web::AuthN;
use App::Netdisco::Web::Static;
use App::Netdisco::Web::Search;
use App::Netdisco::Web::Device;
use App::Netdisco::Web::Report;
use App::Netdisco::Web::AdminTask;
use App::Netdisco::Web::TypeAhead;
use App::Netdisco::Web::PortControl;
use App::Netdisco::Web::Statistics;
use App::Netdisco::Web::Password;
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

# after plugins are loaded, add our own template path
push @{ config->{engines}->{netdisco_template_toolkit}->{INCLUDE_PATH} },
     setting('views');

# any template paths in deployment.yml (should override plugins)
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

# setup for swagger API
my $swagger = Dancer::Plugin::Swagger->instance->doc;
$swagger->{schemes} = ['http','https'];
$swagger->{consumes} = 'application/json';
$swagger->{produces} = 'application/json';
$swagger->{tags} = [
  {name => 'Global'},
  {name => 'Devices',
    description => 'Operations relating to Devices (switches, routers, etc)'},
  {name => 'Nodes',
    description => 'Operations relating to Nodes (end-stations such as printers)'},
  {name => 'NodeIPs',
    description => 'Operations relating to MAC-IP mappings (IPv4 ARP and IPv6 Neighbors)'},
];
$swagger->{securityDefinitions} = {
  APIKeyHeader =>
    { type => 'apiKey', name => 'Authorization', in => 'header' },
  BasicAuth =>
    { type => 'basic'  },
};
$swagger->{security} = [ { APIKeyHeader => [] } ];

# workaround for https://github.com/PerlDancer/Dancer/issues/935
hook after_error_render => sub { setting('layout' => 'main') };

# build list of port detail columns
{
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

  set('port_columns' => \@port_columns);

  # update sidebar_defaults so hooks scanning params see new plugin cols
  setting('sidebar_defaults')->{'device_ports'}->{ $_->{name} } = $_
    for @port_columns;
}

hook 'before' => sub {
  my $key = request->path;
  if (param('tab') and ($key !~ m/ajax/)) {
      $key .= ('/' . param('tab'));
  }
  $key =~ s|.*/(\w+)/(\w+)$|${1}_${2}|;
  var(sidebar_key => $key);

  # copy sidebar defaults into vars so we can mess about with it
  foreach my $sidebar (keys %{setting('sidebar_defaults')}) {
    vars->{'sidebar_defaults'}->{$sidebar} = { map {
      ($_ => setting('sidebar_defaults')->{$sidebar}->{$_}->{'default'})
    } keys %{setting('sidebar_defaults')->{$sidebar}} };
  }
};

hook 'before_template' => sub {
  # search or report from navbar, or reset of sidebar, can ignore params
  return if param('firstsearch')
    or var('sidebar_key') !~ m/^\w+_\w+$/;

  # update defaults to contain the passed url params
  # (this follows initial copy from config.yml, then cookie restore)
  var('sidebar_defaults')->{var('sidebar_key')}->{$_} = param($_)
    for keys %{ var('sidebar_defaults')->{var('sidebar_key')} || {} };
};

hook 'before_template' => sub {
    my $tokens = shift;

    # allow portable static content
    $tokens->{uri_base} = request->base->path
        if request->base->path ne '/';

    # allow portable dynamic content
    $tokens->{uri_for} = sub { uri_for(@_)->path_query };

    # current query string to all resubmit from within ajax template
    my $queryuri = URI->new();
    $queryuri->query_param($_ => param($_))
      for grep {$_ ne 'return_url'} keys %{params()};
    $tokens->{my_query} = $queryuri->query();

    # access to logged in user's roles
    $tokens->{user_has_role}  = sub { user_has_role(@_) };

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

    # helper from NetAddr::MAC for the MAC formatting
    $tokens->{mac_format_call} = 'as_'. lc(param('mac_format'))
      if param('mac_format');

    # allow very long lists of ports
    $Template::Directive::WHILE_MAX = 10_000;

    # allow hash keys with leading underscores
    $Template::Stash::PRIVATE = undef;
};

# workaround for Swagger plugin weird response body
hook 'after' => sub {
    my $r = shift; # a Dancer::Response

    if (request->path eq '/swagger.json') {
        $r->content( to_json( $r->content ) );
        header('Content-Type' => 'application/json');
    }
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

any qr{.*} => sub {
    var('notfound' => true);
    status 'not_found';
    template 'index';
};

{
  # https://github.com/PerlDancer/Dancer/issues/967
  no warnings 'redefine';
  *Dancer::_redirect = sub {
      my ($destination, $status) = @_;
      my $response = Dancer::SharedData->response;
      $response->status($status || 302);
      $response->headers('Location' => $destination);
  };
}

true;
