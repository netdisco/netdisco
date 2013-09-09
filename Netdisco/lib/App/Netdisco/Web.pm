package App::Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;

use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use Socket6 (); # to ensure dependency is met
use HTML::Entities (); # to ensure dependency is met
use URI::QueryParam (); # part of URI, to add helper methods
use Path::Class 'dir';

use App::Netdisco::Web::AuthN;
use App::Netdisco::Web::Static;
use App::Netdisco::Web::Search;
use App::Netdisco::Web::Device;
use App::Netdisco::Web::Report;
use App::Netdisco::Web::AdminTask;
use App::Netdisco::Web::TypeAhead;
use App::Netdisco::Web::PortControl;
use App::Netdisco::Web::About;

sub _load_web_plugins {
  my $plugin_list = shift;

  foreach my $plugin (@$plugin_list) {
      $plugin =~ s/^X::/+App::NetdiscoX::Web::Plugin::/;
      $plugin = 'App::Netdisco::Web::Plugin::'. $plugin
        if $plugin !~ m/^\+/;
      $plugin =~ s/^\+//;

      debug "loading Netdisco plugin $plugin";
      eval "require $plugin";
      error $@ if $@;
  }
}

if (setting('web_plugins') and ref [] eq ref setting('web_plugins')) {
    _load_web_plugins( setting('web_plugins') );
}

if (setting('extra_web_plugins') and ref [] eq ref setting('extra_web_plugins')) {
    unshift @INC, dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'site_plugins')->stringify;
    _load_web_plugins( setting('extra_web_plugins') );
}

# workaround for https://github.com/PerlDancer/Dancer/issues/935
hook after_error_render => sub { setting('layout' => 'main') };

hook 'before_template' => sub {
    my $tokens = shift;

    # allow portable static content
    $tokens->{uri_base} = request->base->path
        if request->base->path ne '/';

    # allow portable dynamic content
    $tokens->{uri_for} = sub { uri_for(@_)->path_query };

    # access to logged in user's roles
    $tokens->{user_has_role}  = sub { user_has_role(@_) };

    # allow very long lists of ports
    $Template::Directive::WHILE_MAX = 10_000;

    # allow hash keys with leading underscores
    $Template::Stash::PRIVATE = undef;
};

get qr{^/(?:login(?:/denied)?)?} => sub {
    template 'index';
};

any qr{.*} => sub {
    var('notfound' => true);
    status 'not_found';
    template 'index';
};

true;
