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
  '_reports_menu' => {},
  '_reports' => {},
  '_report_order' => [qw/Device Port IP Node VLAN Network Wireless/],
);

# this is what Dancer::Template::TemplateToolkit does by default
config->{engines}->{template_toolkit}->{INCLUDE_PATH} ||= [ setting('views') ];

register 'register_template_path' => sub {
  my ($self, $path) = plugin_args(@_);

  if (!$path) {
      return error "bad template path to register_template_paths";
  }

  unshift
    @{ config->{engines}->{template_toolkit}->{INCLUDE_PATH} },
    $path, dir($path, 'views')->stringify;
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

  foreach my $item (@{setting('_reports_menu')->{ $config->{category} }}) {
      if ($item eq $config->{tag}) {
          setting('_reports')->{$config->{tag}} = $config;
          return;
      }
  }

  push @{setting('_reports_menu')->{ $config->{category} }}, $config->{tag};
  setting('_reports')->{$config->{tag}} = $config;
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

This document explains how to configure which plugins are loaded. See
L<App::Netdisco::Manual::WritingPlugins> if you want to develop new plugins.

=head1 Application Configuration

Netdisco configuration supports a C<web_plugins> directive along with the
similar C<extra_web_plugins>. These list, in YAML format, the set of Perl
module names which are the plugins to be loaded. Each item injects one part of
the Netdisco web user interface.

You can override these settings to add, change, or remove entries from the
default lists. Here is an example of the C<web_plugins> list:

 web_plugins:
   - Inventory
   - Report::DuplexMismatch
   - Search::Device
   - Search::Node
   - Search::Port
   - Device::Details
   - Device::Ports

Any change should go into your local C<deployment.yml> configuration file. If
you want to view the default settings, see the C<share/config.yml> file in the
C<App::Netdisco> distribution.

=head1 How to Configure

The C<extra_web_plugins> setting is empty, and used only if you want to add
new plugins but not change the set enabled by default. If you do want to add
to or remove from the default set, then create a version of C<web_plugins>
instead.

Netdisco prepends "C<App::Netdisco::Web::Plugin::>" to any entry in the list.
For example, "C<Inventory>" will load the
C<App::Netdisco::Web::Plugin::Inventory> module.

Such plugin modules can either ship with the App::Netdisco distribution
itself, or be installed separately. Perl uses the standard C<@INC> path
searching mechanism to load the plugin modules.

If an entry in the list starts with a "C<+>" (plus) sign then Netdisco attemps
to load the module as-is, without prepending anything to the name. This allows
you to have App::Netdiso web UI plugins in other namespaces:

 web_plugins:
   - Inventory
   - Search::Device
   - Device::Details
   - +My::Other::Netdisco::Web::Component

The order of the entries is significant. Unsurprisingly, the modules are
loaded in order. Therefore Navigation Bar items appear in the order listed,
and Tabs appear on the Search and Device pages in the order listed, and so on.

Finally, you can also prepend module names with "C<X::>", to support the
"Netdisco extension" namespace. For example, "C<X::Observium>" will load the
L<App::NetdiscoX::Web::Plugin::Observium> module.

=cut

