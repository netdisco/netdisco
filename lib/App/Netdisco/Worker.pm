package App::Netdisco::Worker;

use strict;
use warnings;

use Module::Load ();
use Dancer ':syntax';

# load worker plugins for our workers

sub load_worker_plugins {
  my ($action, $plugin_list) = @_;

  foreach my $plugin (@$plugin_list) {
    $plugin =~ s/^X::/+App::NetdiscoX::Worker::Plugin::/;
    $plugin = 'App::Netdisco::Worker::Plugin::'. $plugin
      if $plugin !~ m/^\+/;
    $plugin =~ s/^\+//;

    next unless $plugin =~ m/::Plugin::${action}(?:::|$)/i;

    debug "loading worker plugin $plugin";
    Module::Load::load $plugin;
  }
}

sub import {
  my ($class, $action) = @_;
  load_worker_plugins( $action, setting('extra_worker_plugins') || [] );
  load_worker_plugins( $action, setting('worker_plugins') || [] );
}

true;
