package App::Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;

use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use Socket6 (); # to ensure dependency is met
use HTML::Entities (); # to ensure dependency is met
use URI::QueryParam (); # part of URI, to add helper methods
use Path::Class 'dir';
use Module::Find ();
use Module::Load ();
use App::Netdisco::Util::Web 'interval_to_daterange';

# can override splats only by loading first
Module::Find::usesub 'App::NetdiscoE::Web';

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

      debug "loading Netdisco plugin $plugin";
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

# workaround for https://github.com/PerlDancer/Dancer/issues/935
hook after_error_render => sub { setting('layout' => 'main') };

# this hook should be loaded _after_ all plugins
hook 'before_template' => sub {
    my $tokens = shift;

    # allow portable static content
    $tokens->{uri_base} = request->base->path
        if request->base->path ne '/';

    # allow portable dynamic content
    $tokens->{uri_for} = sub { uri_for(@_)->path_query };

    # access to logged in user's roles
    $tokens->{user_has_role}  = sub { user_has_role(@_) };

    # create date ranges from within templates
    $tokens->{to_daterange}  = sub { interval_to_daterange(@_) };

    # data structure for DataTables records per page menu
    $tokens->{table_showrecordsmenu} =
      to_json( setting('table_showrecordsmenu') );

    # fix Plugin Template Variables to be only path+query
    $tokens->{$_} = $tokens->{$_}->path_query
      for qw/search_node search_device device_ports/;

    # allow very long lists of ports
    $Template::Directive::WHILE_MAX = 10_000;

    # allow hash keys with leading underscores
    $Template::Stash::PRIVATE = undef;
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
