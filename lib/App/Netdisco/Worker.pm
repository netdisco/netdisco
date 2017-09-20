package App::Netdisco::Worker;

use strict;
use warnings;

use Module::Load ();
use Module::Find qw/findsubmod findallmod/;
use Dancer ':syntax';

# load worker plugins for our action

sub import {
  my ($class, $action) = @_;
  die "missing action\n" unless $action;

  my @user_plugins = @{ setting('extra_worker_plugins') || [] };
  my @check_plugins = findsubmod 'App::Netdisco::Worker::Plugin';
  my @phase_plugins = map { findallmod $_ } @check_plugins;

  foreach my $plugin (@user_plugins, @check_plugins, @phase_plugins) {
    $plugin =~ s/^X::/App::NetdiscoX::Worker::Plugin::/;
    next unless $plugin =~ m/::Plugin::${action}(?:::|$)/i;

    debug "loading worker plugin $plugin";
    Module::Load::load $plugin;
  }
}

true;
