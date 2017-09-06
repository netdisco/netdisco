package App::Netdisco::Worker::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;
use Dancer::Factory::Hook;

use Scope::Guard 'guard';
use aliased 'App::Netdisco::Worker::Status';
use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;

# track the phases seen so we can recall them in order
set( '_nd2worker_hooks' => [] );

register 'register_worker' => sub {
  my ($self, $first, $second) = plugin_args(@_);
  my $workerconf = (ref $first eq 'HASH' ? $first : {});
  my $code = (ref $first eq 'CODE' ? $first : $second);
  return error "bad param to register_worker"
    unless ((ref sub {} eq ref $code) and (ref {} eq ref $workerconf));

  # needs to be here for caller() context
  my ($package, $action, $phase) = ((caller)[0], undef, undef);
  if ($package =~ m/::Plugin::(\w+)$/) {
    $action = lc $1;
  }
  elsif ($package =~ m/::Plugin::(\w+)::(\w+)/) {
    $action = lc $1; $phase = lc $2;
  }
  else { return error "worker Package does not match standard naming" }

  $workerconf->{action}  = $action;
  $workerconf->{phase}   = ($phase || '00init');
  $workerconf->{primary} = ($workerconf->{primary} ? true : false);

  my $worker = sub {
    my $job = shift or return Status->error('missing job param');

    my $no   = (exists $workerconf->{no}   ? $workerconf->{no}   : undef);
    my $only = (exists $workerconf->{only} ? $workerconf->{only} : undef);

    my @newuserconf = ();
    my @userconf = @{ setting('device_auth') || [] };

    # reduce device_auth by driver, worker's only/no
    foreach my $stanza (@userconf) {
      if (ref $job->device) {
        next if $no and check_acl_no($job->device->ip, $no);
        next if $only and not check_acl_only($job->device->ip, $only);
      }
      next if exists $stanza->{driver} and exists $workerconf->{driver}
        and (($stanza->{driver} || '') ne ($workerconf->{driver} || ''));
      push @newuserconf, $stanza;
    }

    # per-device action but no device creds available
    return Status->error('skipped with no device creds')
      if ref $job->device and 0 == scalar @newuserconf;

    # back up and restore device_auth
    my $guard = guard { set(device_auth => \@userconf) };
    set(device_auth => \@newuserconf);

    # run worker
    return $code->($job, $workerconf);
  };

  my $primary = ($workerconf->{primary} ? '_primary' : '');
  my $hook = 'nd2_'. $action .'_'. $workerconf->{phase} . $primary;
  my $store = Dancer::Factory::Hook->instance();

  if (not $store->hook_is_registered($hook)) {
    $store->install_hooks($hook);
    # track just the basic phase names which are used
    push @{ setting('_nd2worker_hooks') }, $hook
      if $workerconf->{phase} ne '00init' and 0 == length($primary);
  }

  # D::Factory::Hook::register_hook() does not work?!
  hook $hook => $worker;
};

register_plugin;
true;

=head1 NAME

App::Netdisco::Worker::Plugin - Netdisco Workers

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

The C<worker_plugins> and C<extra_worker_plugins> settings list in YAML format
the set of Perl module names which are the plugins to be loaded.

Any change should go into your local C<deployment.yml> configuration file. If
you want to view the default settings, see the C<share/config.yml> file in the
C<App::Netdisco> distribution.

=head1 How to Configure

The C<extra_worker_plugins> setting is empty, and used only if you want to add
new plugins but not change the set enabled by default. If you do want to add
to or remove from the default set, then create a version of C<worker_plugins>
instead.

Netdisco prepends "C<App::Netdisco::Worker::Plugin::>" to any entry in the
list.  For example, "C<Discover::Wireless::UniFi>" will load the
C<App::Netdisco::Worker::Plugin::Discover::Wireless::UniFi> package.

You can prepend module names with "C<X::>" as shorthand for the "Netdisco
extension" namespace. For example, "C<X::Macsuck::WirelessNodes::UniFi>" will
load the L<App::NetdiscoX::Worker::Plugin::Macsuck::WirelessNodes::UniFi>
module.

If an entry in the list starts with a "C<+>" (plus) sign then Netdisco attemps
to load the module as-is, without prepending anything to the name. This allows
you to have App::Netdisco Worker plugins in other namespaces.

Plugin modules can either ship with the App::Netdisco distribution itself, or
be installed separately. Perl uses the standard C<@INC> path searching
mechanism to load the plugin modules. See the C<include_paths> and
C<site_local_files> settings in order to modify C<@INC> for loading local
plugins. As an example, if your plugin is called
"App::NetdiscoX::Worker::Plugin::MyPluginName" then it could live at:

 ~netdisco/nd-site-local/lib/App/NetdiscoX/Worker/Plugin/MyPluginName.pm

The order of the entries is significant, workers being executed in the order
which they appear in C<worker_plugins> and C<extra_worker_plugins> (although
see L<App::Netdisco::Manual::WritingWorkers> for caveats).

=cut

