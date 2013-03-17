package App::Netdisco::Web::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;

set(
  'navbar_items' => [],
  'search_tabs'  => [],
  'device_tabs'  => [],
  'reports_menu' => {},
  'reports' => {},
  'report_order' => [qw/Device Port Node VLAN Network Wireless/],
);

# this is what Dancer::Template::TemplateToolkit does by default
config->{engines}->{template_toolkit}->{INCLUDE_PATH} ||= [ setting('views') ];

register 'register_template_path' => sub {
  my ($self, $path) = plugin_args(@_);

  if (!length $path) {
      error "bad template path to register_template_paths";
      return;
  }

  unshift
    @{ config->{engines}->{template_toolkit}->{INCLUDE_PATH} },
    $path;
};

register 'register_navbar_item' => sub {
  my ($self, $config) = plugin_args(@_);

  if (!length $config->{tag}
      or !length $config->{path}
      or !length $config->{label}) {

      error "bad config to register_navbar_item";
      return;
  }

  foreach my $item (@{ setting('navbar_items') }) {
      if ($item->{tag} eq $config->{tag}) {
          $item = $config;
          return;
      }
  }

  push @{ setting('navbar_items') }, $config;
};

sub _register_tab {
  my ($nav, $config) = @_;
  my $stash = setting("${nav}_tabs");

  if (!length $config->{tag}
      or !length $config->{label}) {

      error "bad config to register_${nav}_item";
      return;
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
  my @categories = @{ setting('report_order') };

  if (!length $config->{category}
      or !length $config->{tag}
      or !length $config->{label}
      or 0 == scalar grep {$config->{category} eq $_} @categories) {

      error "bad config to register_report";
      return;
  }

  foreach my $item (@{setting('reports_menu')->{ $config->{category} }}) {
      if ($item eq $config->{tag}) {
          setting('reports')->{$config->{tag}} = $config;
          return;
      }
  }

  push @{setting('reports_menu')->{ $config->{category} }}, $config->{tag};
  setting('reports')->{$config->{tag}} = $config;
};

register_plugin;
true;

=head1 NAME

App::Netdisco::Web::Plugin - Plugin subsystem for App::Netdisco Web UI components

=head1 Introduction

L<App::Netdisco>'s plugin subsystem allows the user more control of Netdisco
UI components displayed in the web browser. Plugins can be distributed
independently from Netdisco and are a better alternative to source code
patches.

The following UI components are implemented as plugins:

=over 4

=item *

Navigation Bar items (e.g. Inventory link)

=item *

Tabs for Search and Device pages

=item *

Reports (pre-canned searches)

=back

This document explains how to configure which plugins are loaded. See
L<App::Netdisco::Manual::WritingPlugins> if you want to develop new plugins.

=head1 Application Configuration

In the main C<config.yml> file for App::Netdisco (located in C<share/...>)
you'll find the C<web_plugins> configuration directive. This lists, in YAML
format, a set of Perl module names (or partial names) which are the plugins to
be loaded. For example:

 web_plugins:
   - Inventory
   - Report::DuplexMismatch
   - Search::Device
   - Search::Node
   - Search::Port
   - Device::Details
   - Device::Ports

When the name is specified as above, App::Netdisco automatically prepends
"C<App::Netdisco::Web::Plugin::>" to the name. This makes, for example,
L<App::Netdisco::Web::Plugin::Inventory>. This is the module which is loaded
to add a user interface component.

Such plugin modules can either ship with the App::Netdisco distribution
itself, or be installed separately. Perl uses the standard C<@INC> path
searching mechanism to load the plugin modules.

If an entry in the C<web_plugins> list starts with a "C<+>" (plus) sign then
App::Netdisco attemps to load the module as-is, without prepending anything to
the name. This allows you to have App::Netdiso web UI plugins in other
namespaces:

 web_plugins:
   - Inventory
   - Search::Device
   - Device::Details
   - +My::Other::Netdisco::Web::Component

The order of the entries in C<web_plugins> is significant. Unsurprisingly, the
modules are loaded in order. Therefore Navigation Bar items appear in the
order listed, and Tabs appear on the Search and Device pages in the order
listed.

The consequence of this is that if you want to change the order (or add or
remove entries) then simply edit the C<web_plugins> setting. In fact, we
recommend adding this setting to your C<< <environment>.yml >> file and
leaving the C<config.yml> file alone. Your Environment's version will take
prescedence.

Finally, if you want to add components without completely overriding the
C<web_plugins> setting, use the C<extra_web_plugins> setting instead in your
Environment configuration. Any Navigation Bar items or Page Tabs are added
after those in C<web_plugins>.

=cut

