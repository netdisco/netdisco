package App::Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;

use Dancer::Plugin::DBIC;

use Socket6 (); # to ensure dependency is met
use HTML::Entities (); # to ensure dependency is met
use URI::QueryParam (); # part of URI, to add helper methods

use App::Netdisco::Web::AuthN;
use App::Netdisco::Web::Search;
use App::Netdisco::Web::Device;
use App::Netdisco::Web::Report;
use App::Netdisco::Web::TypeAhead;
use App::Netdisco::Web::PortControl;

sub _load_web_plugins {
  my $plugin_list = shift;

  foreach my $plugin (@$plugin_list) {
      $plugin = 'App::Netdisco::Web::Plugin::'. $plugin
        unless $plugin =~ m/^\+/;
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
    _load_web_plugins( setting('extra_web_plugins') );
}

hook 'before_template' => sub {
    my $tokens = shift;

    # allow portable static content
    $tokens->{uri_base} = request->base->path
        if request->base->path ne '/';

    # allow portable dynamic content
    $tokens->{uri_for} = sub { uri_for(@_)->path_query() };

    # allow very long lists of ports
    $Template::Directive::WHILE_MAX = 10_000;
};

get '/' => sub {
    template 'index';
};

any qr{.*} => sub {
    var('notfound' => true);
    status 'not_found';
    template 'index';
};

true;
