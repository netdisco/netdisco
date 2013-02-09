package App::Netdisco::Web::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;

set(
  'navbar_items' => [],
  'search_tabs'  => [],
  'device_tabs'  => [],
);

register 'register_navbar_item' => sub {
  my ($self, $config) = plugin_args(@_);

  die "bad config to register_navbar_item\n"
    unless length $config->{id}
       and length $config->{path}
       and length $config->{label};

  foreach my $item (@{ setting('navbar_items') }) {
      if ($item->{id} eq $config->{id}) {
          $item = $config;
          return;
      }
  }

  push @{ setting('navbar_items') }, $config;
};

sub _register_tab {
  my ($nav, $config) = @_;
  my $stash = setting("${nav}_tabs");

  die "bad config to register_${nav}_tab\n"
    unless length $config->{id}
       and length $config->{label};

  foreach my $item (@{ $stash }) {
      if ($item->{id} eq $config->{id}) {
          $item = $config;
          return;
      }
  }

  push @{ $stash }, $config;
}

register 'register_search_tab' => sub {
  my ($self, $config) = plugin_args(@_);
  _register_tab('search', $config);
};

register 'register_device_tab' => sub {
  my ($self, $config) = plugin_args(@_);
  _register_tab('device', $config);
};

register_plugin;
true;
