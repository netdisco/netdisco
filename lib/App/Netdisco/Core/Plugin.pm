package App::Netdisco::Core::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;
use Dancer::Factory::Hook;

use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;
use Scope::Guard;
use Try::Tiny;

Dancer::Factory::Hook->instance->install_hooks(
  map {("before_$_", $_, "after_$_")}
      @{ setting('core_phases') }
);

register 'register_core_driver' => sub {
  my ($self, $driverconf, $code) = @_;
  return error "bad param to register_core_driver"
    unless ((ref sub {} eq ref $code) and (ref {} eq ref $driverconf)
      and exists $driverconf->{phase} and exists $driverconf->{driver}
      and Dancer::Factory::Hook->instance->hook_is_registered($driverconf->{phase}));

  # needs to be here for caller() context
  $driverconf->{plugin} = (caller)[0];

  my $hook = sub {
    my $device = shift or return false;

    my $no   = (exists $driverconf->{no}   ? $driverconf->{no}   : undef);
    my $only = (exists $driverconf->{only} ? $driverconf->{only} : undef);

    my @newuserconf = ();
    my @userconf = @{ setting('device_auth') || [] };

    # reduce device_auth by driver, plugin, driver's only/no
    foreach my $stanza (@userconf) {
      next if $no and check_acl_no($device, $no);
      next if $only and not check_acl_only($device, $only);
      next if exists $stanza->{driver}
        and (($stanza->{driver} || '') ne $driverconf->{driver});
      next if exists $stanza->{plugin}
        and (($stanza->{plugin} || '') ne $driverconf->{plugin});
      push @newuserconf, $stanza;
    }

    # back up and restore device_auth
    return false unless scalar @newuserconf;
    my $guard = guard { set(device_auth => \@userconf) };
    set(device_auth => \@newuserconf);

    # run driver
    my $happy = false;
    try {
      $code->($device, $driverconf);
      $happy = true;
    }
    catch { debug $_ };
    return $happy;
  };

  Dancer::Factory::Hook->instance->register_hook($driverconf->{phase}, $hook);
};

register_plugin;
true;

=head1 NAME

App::Netdisco::Core::Plugin - Netdisco Backend Drivers

=head1 Introduction

L<App::Netdisco>'s plugin system allows users to create backend I<drivers>
which use different I<transports> to gather information from network devices
and store in the database.

For example, transports might be SNMP, SSH, or HTTPS. Drivers might be
combining those transports with application protocols such as SNMP, NETCONF
(OpenConfig with XML), RESTCONF (OpenConfig with JSON), eAPI, or even CLI
scraping.

Drivers can be restricted to certain vendor platforms using familiar ACL
syntax. They are also attached to specific phases in Netdisco's backend
operation.

=head1 Application Configuration

The C<collector_plugins> and C<extra_collector_plugins> settings list in YAML
format the set of Perl module names which are the plugins to be loaded.

Any change should go into your local C<deployment.yml> configuration file. If
you want to view the default settings, see the C<share/config.yml> file in the
C<App::Netdisco> distribution.

Driver phases are in the C<core_phases> setting and for a given backend
action, the registered drivers at one or more phases will be executed if they
apply to the target device. Each phase ("X") also gets a C<before_X> and
C<after_X> phase added for preparatory or optional work, respectively.

=head1 How to Configure

The C<extra_collector_plugins> setting is empty, and used only if you want to
add new plugins but not change the set enabled by default. If you do want to
add to or remove from the default set, then create a version of
C<collector_plugins> instead.

Netdisco prepends "C<App::Netdisco::Core::Plugin::>" to any entry in the list.
For example, "C<Discover::Wireless::UniFi>" will load the
C<App::Netdisco::Core::Plugin::Discover::Wireless::UniFi> package.

If an entry in the list starts with a "C<+>" (plus) sign then Netdisco attemps
to load the module as-is, without prepending anything to the name. This allows
you to have App::Netdiso Core plugins in other namespaces.

Plugin modules can either ship with the App::Netdisco distribution itself, or
be installed separately. Perl uses the standard C<@INC> path searching
mechanism to load the plugin modules. See the C<include_paths> and
C<site_local_files> settings in order to modify C<@INC> for loading local
plugins. As an example, if your plugin is called
"App::NetdiscoX::Core::Plugin::MyPluginName" then it could live at:

 ~netdisco/nd-site-local/lib/App/NetdiscoX/Core/Plugin/MyPluginName.pm

The order of the entries is significant, drivers being executed in the order
which they appear in C<collector_plugins> and C<extra_collector_plugins>
(although see L<App::Netdisco::Manual::WritingBackendDrivers> for caveats).

Finally, you can also prepend module names with "C<X::>", to support the
"Netdisco extension" namespace. For example,
"C<X::Macsuck::WirelessNodes::UniFi>" will load the
L<App::NetdiscoX::Core::Plugin::Macsuck::WirelessNodes::UniFi> module.

=cut

