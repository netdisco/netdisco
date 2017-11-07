package App::Netdisco::Worker::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;

use Scope::Guard 'guard';
use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;

register 'register_worker' => sub {
  my ($self, $first, $second) = plugin_args(@_);

  my $workerconf = (ref $first eq 'HASH' ? $first : {});
  my $code = (ref $first eq 'CODE' ? $first : $second);
  return error "bad param to register_worker"
    unless ((ref sub {} eq ref $code) and (ref {} eq ref $workerconf));

  my $package = (caller)[0];
  if ($package =~ m/Plugin::(\w+)(?:::(\w+))?/) {
    $workerconf->{action}    = lc($1);
    $workerconf->{namespace} = lc($2) if $2;
  }
  return error "failed to parse action in '$package'"
    unless $workerconf->{action};

  $workerconf->{phase}     ||= 'user';
  $workerconf->{namespace} ||= '_base_';
  $workerconf->{priority}  ||= (exists $workerconf->{driver}
    ? setting('driver_priority')->{$workerconf->{driver}} : 0);

  my $worker = sub {
    my $job = shift or die 'missing job param';
    # use DDP; p $workerconf;

    # update job's record of namespace and priority
    # check to see if this namespace has already passed at higher priority
    return if $job->namespace_passed($workerconf);

    my @newuserconf = ();
    my @userconf = @{ setting('device_auth') || [] };

    # worker might be vendor/platform specific
    if (ref $job->device) {
      my $no   = (exists $workerconf->{no}   ? $workerconf->{no}   : undef);
      my $only = (exists $workerconf->{only} ? $workerconf->{only} : undef);

      return $job->add_status( Status->defer('worker is not applicable to this device') )
        if ($no and check_acl_no($job->device, $no))
           or ($only and not check_acl_only($job->device, $only));

      # reduce device_auth by driver and action filters
      foreach my $stanza (@userconf) {
        next if exists $stanza->{driver} and exists $workerconf->{driver}
          and (($stanza->{driver} || '') ne ($workerconf->{driver} || ''));

        next if exists $stanza->{action}
          and not _find_matchaction($workerconf, lc($stanza->{action}));

        push @newuserconf, $stanza;
      }

      # per-device action but no device creds available
      return $job->add_status( Status->defer('deferred job with no device creds') )
        if 0 == scalar @newuserconf;
    }

    # back up and restore device_auth
    my $guard = guard { set(device_auth => \@userconf) };
    set(device_auth => \@newuserconf);

    # run worker
    $code->($job, $workerconf);
  };

  # store the built worker as Worker.pm will build the dispatch order later on
  push @{ vars->{'workers'}
              ->{$workerconf->{phase}}
              ->{$workerconf->{namespace}}
              ->{$workerconf->{priority}} }, $worker;
};

sub _find_matchaction {
  my ($conf, $action) = @_;
  return true if !defined $action;
  $action = [$action] if ref [] ne ref $action;

  foreach my $f (@$action) {
    return true if
      $f eq $conf->{action} or $f eq "$conf->{action}::$conf->{namespace}";
  }
  return false;
}

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
syntax. They are also attached to specific actions in Netdisco's backend
operation (discover, macsuck, etc).

=head1 Application Configuration

The C<worker_plugins> and C<extra_worker_plugins> settings list in YAML format
the set of Perl module names which are the plugins to be loaded.

Any change should go into your local C<deployment.yml> configuration file. If
you want to view the default settings, see the C<share/config.yml> file in the
C<App::Netdisco> distribution.

=head1 How to Configure

The C<extra_worker_plugins> setting is empty, and used when you want to add
new plugins and not change the set enabled by default. If you do want to add
to or remove from the default set, then create a version of C<worker_plugins>
instead.

Netdisco prepends "C<App::Netdisco::Worker::Plugin::>" to any entry in the
list. For example, "C<Discover::Wireless::UniFi>" will load the
C<App::Netdisco::Worker::Plugin::Discover::Wireless::UniFi> package.

You can prepend module names with "C<X::>" as shorthand for the "Netdisco
extension" namespace. For example, "C<X::Macsuck::WirelessNodes::UniFi>" will
load the L<App::NetdiscoX::Worker::Plugin::Macsuck::WirelessNodes::UniFi>
module.

If an entry in the list starts with a "C<+>" (plus) sign then Netdisco attemps
to load the module as-is, without prepending anything to the name. This allows
you to have worker plugins in any namespace.

Plugin modules can either ship with the App::Netdisco distribution itself, or
be installed separately. Perl uses the standard C<@INC> path searching
mechanism to load the plugin modules. See the C<include_paths> and
C<site_local_files> settings in order to modify C<@INC> for loading local
plugins.

As an example, if you set C<site_local_files> to be true, set
C<extra_worker_plugins> to be C<'X::MyPluginName'> (the plugin package is
"App::NetdiscoX::Worker::Plugin::MyPluginName") then your plugin lives at:

 ~netdisco/nd-site-local/lib/App/NetdiscoX/Worker/Plugin/MyPluginName.pm

The order of the entries is significant, workers being executed in the order
which they appear in C<extra_worker_plugins> followed by C<worker_plugins>.

See L<App::Netdisco::Manual::WritingWorkers> for further details.
=cut

