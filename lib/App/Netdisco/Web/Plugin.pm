package App::Netdisco::Web::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;

use Path::Class 'dir';

set(
  '_additional_css'         => [],
  '_additional_javascript'  => [],
  '_extra_device_port_cols' => [],
  '_extra_device_details'   => [],
  '_navbar_items' => [],
  '_search_tabs'  => [],
  '_device_tabs'  => [],
  '_admin_tasks'  => {},
  '_admin_order'  => [],
  '_reports_menu' => {},
  '_reports' => {},
  '_report_order' => [qw/Device Port IP Node VLAN Network Wireless/, 'My Reports'],
);

# this is what Dancer::Template::TemplateToolkit does by default
config->{engines}->{netdisco_template_toolkit}->{INCLUDE_PATH} ||= [ setting('views') ];

register 'register_template_path' => sub {
  my ($self, $path) = plugin_args(@_);

  if (!$path) {
      return error "bad template path to register_template_paths";
  }

  unshift @{ config->{engines}->{netdisco_template_toolkit}->{INCLUDE_PATH} },
       dir($path, 'views')->stringify;
};

sub _register_include {
  my ($type, $plugin) = @_;

  if (!$type) {
      return error "bad type to _register_include";
  }

  if (!$plugin) {
      return error "bad plugin name to register_$type";
  }

  push @{ setting("_additional_$type") }, $plugin;
}

register 'register_css' => sub {
  my ($self, $plugin) = plugin_args(@_);
  _register_include('css', $plugin);
};

register 'register_javascript' => sub {
  my ($self, $plugin) = plugin_args(@_);
  _register_include('javascript', $plugin);
};

register 'register_device_port_column' => sub {
  my ($self, $config) = plugin_args(@_);
  $config->{default} ||= '';
  $config->{position} ||= 'right';

  if (!$config->{name} or !$config->{label}) {
      return error "bad config to register_device_port_column";
  }

  foreach my $item (@{ setting('_extra_device_port_cols') }) {
      if ($item->{name} eq $config->{name}) {
          $item = $config;
          return;
      }
  }

  push @{ setting('_extra_device_port_cols') }, $config;
};

register 'register_device_details' => sub {
  my ($self, $config) = plugin_args(@_);

  if (!$config->{name} or !$config->{label}) {
      return error "bad config to register_device_details";
  }

  foreach my $item (@{ setting('_extra_device_details') }) {
      if ($item->{name} eq $config->{name}) {
          $item = $config;
          return;
      }
  }

  push @{ setting('_extra_device_details') }, $config;
};

register 'register_navbar_item' => sub {
  my ($self, $config) = plugin_args(@_);

  if (!$config->{tag}
      or !$config->{path}
      or !$config->{label}) {

      return error "bad config to register_navbar_item";
  }

  foreach my $item (@{ setting('_navbar_items') }) {
      if ($item->{tag} eq $config->{tag}) {
          $item = $config;
          return;
      }
  }

  push @{ setting('_navbar_items') }, $config;
};

register 'register_admin_task' => sub {
  my ($self, $config) = plugin_args(@_);

  if (!$config->{tag}
      or !$config->{label}) {

      return error "bad config to register_admin_task";
  }

  push @{ setting('_admin_order') }, $config->{tag};
  setting('_admin_tasks')->{ $config->{tag} } = $config;
};

sub _register_tab {
  my ($nav, $config) = @_;
  my $stash = setting("_${nav}_tabs");

  if (!$config->{tag}
      or !$config->{label}) {

      return error "bad config to register_${nav}_item";
  }

  foreach my $item (@{ $stash }) {
      if ($item->{tag} eq $config->{tag}) {
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

register 'register_report' => sub {
  my ($self, $config) = plugin_args(@_);
  my @categories = @{ setting('_report_order') };

  if (!$config->{category}
      or !$config->{tag}
      or !$config->{label}
      or 0 == scalar grep {$config->{category} eq $_} @categories) {

      return error "bad config to register_report";
  }

  if (0 == scalar grep {$_ eq $config->{tag}}
                       @{setting('_reports_menu')->{ $config->{category} }}) {
      push @{setting('_reports_menu')->{ $config->{category} }}, $config->{tag};
  }

  foreach my $tag (@{setting('_reports_menu')->{ $config->{category} }}) {
      if ($config->{tag} eq $tag) {
          setting('_reports')->{$tag} = $config;

          foreach my $rconfig (@{setting('reports')}) {
              if ($rconfig->{tag} eq $tag) {
                  setting('_reports')->{$tag}->{'rconfig'} = $rconfig;
                  last;
              }
          }
      }
  }
};

register_plugin;
true;

=head1 NAME

App::Netdisco::Web::Plugin - Netdisco Web UI components

=head1 Introduction

L<App::Netdisco>'s plugin system allows you more control of what Netdisco
components are displayed in the web interface. Plugins can be distributed
independently from Netdisco and are a better alternative to source code
patches.

The following web interface components are implemented as plugins:

=over 4

=item *

Navigation Bar items (e.g. Inventory link)

=item *

Tabs for Search and Device pages

=item *

Reports (pre-canned searches)

=item *

Additional Device Port Columns

=item *

Additional Device Details

=item *

Admin Menu function (job control, manual topology, pseudo devices)

=back

See L<https://github.com/netdisco/netdisco/wiki/Web-Plugins> for details.

=cut

