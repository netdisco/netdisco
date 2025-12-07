package App::Netdisco::Worker::Loader;

use strict;
use warnings;

use Module::Load ();
use Dancer qw/:moose :syntax/;

use Moo::Role;
use namespace::clean;

has [qw/workers_check
        workers_early
        workers_main
        workers_user
        workers_store
        workers_late
        transport_required/] => ( is => 'rw' );

sub load_workers {
  my $self = shift;
  my $action = $self->job->action or die "missing action\n";

  my @core_plugins = @{ setting('worker_plugins') || [] };
  my @user_plugins = @{ setting('extra_worker_plugins') || [] };

  # load worker plugins for our action
  foreach my $plugin (@user_plugins, @core_plugins) {
    $plugin =~ s/^X::/+App::NetdiscoX::Worker::Plugin::/;
    $plugin = 'App::Netdisco::Worker::Plugin::'. $plugin
      if $plugin !~ m/^\+/;
    $plugin =~ s/^\+//;

    next unless $plugin =~ m/::Plugin::(?:${action}|Internal)(?:::|$)/i;
    $ENV{ND2_LOG_PLUGINS} && debug "loading worker plugin $plugin";
    Module::Load::load $plugin;
  }

  # also load a shim for any configured python worker
  if (setting('enable_python_worklets')) {
      # the way this works is to pass the action name to import()
      Module::Load::load 'App::Netdisco::Worker::Plugin::PythonShim', $action;
  }

  my $workers = vars->{'workers'}->{$action} || {};

  # need to merge in internal workers without overriding action workers
  # we also drop any "stage" (sub-namespace) and install to "__internal__"
  # which has higher run priority than "_base_" and any other.

  foreach my $phase (qw/check early main user store late/) {
    next if exists $workers->{$phase}->{'__internal__'};

    next unless exists vars->{'workers'}->{'internal'}
      and exists vars->{'workers'}->{'internal'}->{$phase};
    my $internal = vars->{'workers'}->{'internal'};

    # the namespace of an internal worker is actually the worker name so must
    # be sorted in order to "preserve" the plugin load order
    foreach my $namespace (sort keys %{ $internal->{$phase} }) {
      foreach my $priority (keys %{ $internal->{$phase}->{$namespace} }) {
        push @{ $workers->{$phase}->{'__internal__'}->{$priority} },
          @{ $internal->{$phase}->{$namespace}->{$priority} };
      }
    }
  }

  # use DDP; my $x = vars{'workers'}; p $x; p $workers;

  # now vars->{workers} is populated, we set the dispatch order
  my $driverless_main = 0;

  foreach my $phase (qw/check early main user store late/) {
    my $pname = "workers_${phase}";
    my @wset = ();

    foreach my $namespace (sort keys %{ $workers->{$phase} }) {
      # priorities are run backwards, low to high, to allow data overriding
      foreach my $priority (sort {$a <=> $b}
                            keys %{ $workers->{$phase}->{$namespace} }) {

        ++$driverless_main if $phase eq 'main'
          and ($priority == 0 or $priority == setting('driver_priority')->{'direct'});
        push @wset, @{ $workers->{$phase}->{$namespace}->{$priority} };
      }
    }

    $self->$pname( \@wset );
  }

  $self->transport_required( $driverless_main ? false : true );
}

true;
