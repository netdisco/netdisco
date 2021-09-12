package App::Netdisco::Worker::Plugin;

use Dancer ':syntax';
use Dancer::Plugin;

use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;
use aliased 'App::Netdisco::Worker::Status';
use Scope::Guard 'guard';
use Storable 'dclone';

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
    ? (setting('driver_priority')->{$workerconf->{driver}} || 0) : 0);

  my $worker = sub {
    my $job = shift or die 'missing job param';
    # use DDP; p $workerconf;

    debug sprintf '-> run worker %s/%s/%s',
      @$workerconf{qw/phase namespace priority/};

    return if $job->is_cancelled;

    # check to see if this namespace has already passed at higher priority
    # and also update job's record of namespace and priority
    return $job->add_status( Status->info('skip: namespace passed at higher priority') )
      if $job->namespace_passed($workerconf);

    # support part-actions via action::namespace
    if ($job->only_namespace and $workerconf->{phase} ne 'check') {
      return unless $workerconf->{namespace} eq lc( $job->only_namespace )
        or (($job->only_namespace ne 'hooks') and ($workerconf->{phase} eq 'early')
             and ($job->device and not $job->device->in_storage));
    }

    my @newuserconf = ();
    my @userconf = @{ dclone (setting('device_auth') || []) };

    # worker might be vendor/platform specific
    if (ref $job->device) {
      my $no   = (exists $workerconf->{no}   ? $workerconf->{no}   : undef);
      my $only = (exists $workerconf->{only} ? $workerconf->{only} : undef);

      return $job->add_status( Status->info('skip: acls restricted') )
        if ($no and check_acl_no($job->device, $no))
           or ($only and not check_acl_only($job->device, $only));

      # reduce device_auth by driver and action filters
      foreach my $stanza (@userconf) {
        next if exists $stanza->{driver} and exists $workerconf->{driver}
          and (($stanza->{driver} || '') ne ($workerconf->{driver} || ''));

        # filter here rather than in Runner as runner does not know namespace
        next if exists $stanza->{action}
          and not _find_matchaction($workerconf, lc($stanza->{action}));

        push @newuserconf, dclone $stanza;
      }

      # per-device action but no device creds available
      return $job->add_status( Status->info('skip: driver or action not applicable') )
        if 0 == scalar @newuserconf && $job->action ne "delete";
    }

    # back up and restore device_auth
    my $guard = guard { set(device_auth => \@userconf) };
    set(device_auth => \@newuserconf);
    # use DDP; p @newuserconf;

    # run worker
    $code->($job, $workerconf);
  };

  # store the built worker as Worker.pm will build the dispatch order later on
  push @{ vars->{'workers'}->{$workerconf->{action}}
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

See L<https://github.com/netdisco/netdisco/wiki/Backend-Plugins> for details.

=cut

