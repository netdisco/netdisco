package App::Netdisco::Core::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;
use Dancer::Factory::Hook;

use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;
use Scope::Guard;
use Try::Tiny;

register 'register_core_worker' => sub {
  my ($self, $workerconf, $code) = @_;
  return error "bad param to register_core_worker"
    unless ((ref sub {} eq ref $code) and (ref {} eq ref $workerconf)
                                      and exists $workerconf->{driver});

  # needs to be here for caller() context
  my ($package, $phase) = ((caller)[0], undef);
  if ($package =~ m/::(Discover|Arpnip|Macsuck|Expire|Nbtstat)::(\w+)/) {
    $phase = lc( $1 .'_'. $2 );
  }
  else { return error "worker Package does not match standard naming" }

  $workerconf->{hook} ||= 'after';
  return error "bad hook param to register_core_worker"
    unless $workerconf->{hook} =~ m/^(?:before|on|after)$/;

  my $worker = sub {
    my $job = shift or return false;

    my $no   = (exists $workerconf->{no}   ? $workerconf->{no}   : undef);
    my $only = (exists $workerconf->{only} ? $workerconf->{only} : undef);

    my @newuserconf = ();
    my @userconf = @{ setting('device_auth') || [] };

    # reduce device_auth by driver, plugin, worker's only/no
    foreach my $stanza (@userconf) {
      if (ref $job->device) {
        next if $no and check_acl_no($job->device->ip, $no);
        next if $only and not check_acl_only($job->device->ip, $only);
      }
      next if exists $stanza->{driver}
        and (($stanza->{driver} || '') ne $workerconf->{driver});
      push @newuserconf, $stanza;
    }

    # back up and restore device_auth
    return false unless scalar @newuserconf;
    my $guard = guard { set(device_auth => \@userconf) };
    set(device_auth => \@newuserconf);

    # run worker
    my $happy = false;
    try {
      my @result = $code->($job, $workerconf);
      $happy = true;
    }
    catch { debug $_ };
    return @result if $happy; # FIXME
  };

  my $hook = $workerconf->{hook} .'_'. $phase;
  Dancer::Factory::Hook->instance->install_hooks($hook)
    unless Dancer::Factory::Hook->instance->hook_is_registered($hook);

  Dancer::Factory::Hook->instance->register_hook($hook, $worker);
};

register_plugin;
true;

=head1 NAME

App::Netdisco::Core::Plugin - Netdisco Core Workers

=head1 Introduction

L<App::Netdisco>'s plugin system allows users to write I<workers> to gather
information from network devices using different I<transports> and store
results in the database.

For example, transports might be SNMP, SSH, or HTTPS. Workers might be
combining those transports with application protocols such as SNMP, NETCONF
(OpenConfig with XML), RESTCONF (OpenConfig with JSON), eAPI, or even CLI
scraping. The combination of transport and protocol is known as a I<driver>.

Workers can be restricted to certain vendor platforms using familiar ACL
syntax. They are also attached to specific phases in Netdisco's backend
operation (discover, macsuck, etc).

=head1 Application Configuration

The C<core_plugins> and C<extra_core_plugins> settings list in YAML format the
set of Perl module names which are the plugins to be loaded.

Any change should go into your local C<deployment.yml> configuration file. If
you want to view the default settings, see the C<share/config.yml> file in the
C<App::Netdisco> distribution.

=head1 How to Configure

The C<extra_core_plugins> setting is empty, and used only if you want to add
new plugins but not change the set enabled by default. If you do want to add
to or remove from the default set, then create a version of C<core_plugins>
instead.

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

The order of the entries is significant, workers being executed in the order
which they appear in C<core_plugins> and C<extra_core_plugins> (although see
L<App::Netdisco::Manual::WritingCoreWorkers> for caveats).

Finally, you can also prepend module names with "C<X::>", to support the
"Netdisco extension" namespace. For example,
"C<X::Macsuck::WirelessNodes::UniFi>" will load the
L<App::NetdiscoX::Core::Plugin::Macsuck::WirelessNodes::UniFi> module.

=cut

