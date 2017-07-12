package App::Netdisco::Core::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;
use Dancer::Hook;

use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;
use Try::Tiny;

Dancer::Hook->instance->register_hooks_name(
  map {("before_$_", $_, "after_$_")}
      @{ setting('core_phases') }
);

# cache hints for working through phases
set(
  map {("_phase_before_$_" => {}, "_phase_$_" => {}, "_phase_after_$_" => {})}
      @{ setting('core_phases') },
  # TODO: store in here (caller)[0] => $args
);

register 'register_core_action' => sub {
  my ($self, $code, $args) = @_;
  return error "bad param to register_core_action"
    unless ref sub {} eq ref $code and ref {} eq ref $args
      and exists $args->{action}
      and Dancer::Hook->hook_is_registered($args->{action});

  my $no   = $args->{no};
  my $only = $args->{only};
  my $store = Dancer::Factory::Hook->instance;

  my $hook = sub {
    my $device = shift or return -1;
    return 0 if ($no and check_acl_no($device, $no))
      or ($only and not check_acl_only($device, $only));

    my $happy = false;
    try {
      $code->($args);
      $happy = true;
    };

    return ($happy ? ($args->{final} ? 1 : 0) : -1);
  };

  if ($args->{final} and $args->{action} !~ m/^(?:before|after)_/) {
    unshift @{$store->hooks->{ $args->{action} }}, $hook;
  }
  else {
    push @{$store->hooks->{ $args->{action} }}, $hook;
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

