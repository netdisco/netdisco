package App::Netdisco::Worker;

use strict;
use warnings;

use Module::Load ();
use Module::Find qw/findsubmod findallmod/;

use Dancer ':syntax';
use Dancer::Factory::Hook;

sub import {
  my ($class, $action) = @_;
  die "missing action\n" unless $action;

  my @user_plugins = @{ setting('extra_worker_plugins') || [] };
  my @check_plugins = findsubmod 'App::Netdisco::Worker::Plugin';
  my @phase_plugins = map { findallmod $_ } @check_plugins;

  # load worker plugins for our action
  foreach my $plugin (@user_plugins, @check_plugins, @phase_plugins) {
    $plugin =~ s/^X::/App::NetdiscoX::Worker::Plugin::/;
    next unless $plugin =~ m/::Plugin::${action}(?:::|$)/i;

    debug "loading worker plugin $plugin";
    Module::Load::load $plugin;
  }

  # now vars->{workers} is populated, we set the dispatch order
  my $workers = vars->{'workers'}->{$action} || {};
  # use DDP; p vars->{'workers'};

  foreach my $phase (qw/check early main user/) {
    foreach my $namespace (sort keys %{ $workers->{$phase} }) {
      foreach my $priority (sort {$b <=> $a}
                            keys %{ $workers->{$phase}->{$namespace} }) {

        # D::Factory::Hook::register_hook() does not work?!
        hook "nd2_core_${phase}" => $_
          for @{ $workers->{$phase}->{$namespace}->{$priority} };
      }
    }
  }
}

true;
