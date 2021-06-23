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
        workers_late/] => ( is => 'rw' );

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

    next unless $plugin =~ m/::Plugin::${action}(?:::|$)/i;
    $ENV{ND2_LOG_PLUGINS} && debug "loading worker plugin $plugin";
    Module::Load::load $plugin;
  }

  # now vars->{workers} is populated, we set the dispatch order
  my $workers = vars->{'workers'}->{$action} || {};
  #use DDP; p vars->{'workers'};

  foreach my $phase (qw/check early main user store late/) {
    my $pname = "workers_${phase}";
    my @wset = ();

    foreach my $namespace (sort keys %{ $workers->{$phase} }) {
      foreach my $priority (sort {$b <=> $a}
                            keys %{ $workers->{$phase}->{$namespace} }) {
        push @wset, @{ $workers->{$phase}->{$namespace}->{$priority} };
      }
    }

    $self->$pname( \@wset );
  }
}

true;
