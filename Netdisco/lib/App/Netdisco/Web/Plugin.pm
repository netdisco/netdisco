package App::Netdisco::Web::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;

set('navbar_items' => []);

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

register_plugin;
true;
