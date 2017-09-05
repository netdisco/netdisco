package App::Netdisco::Worker;

use strict;
use warnings;

use Module::Load ();
use Dancer ':syntax';

# load worker plugins for our workers
# NOTE: this package is loaded for all actions whether backend or netdisco-do

sub load_worker_plugins {
  my $plugin_list = shift;

  foreach my $plugin (@$plugin_list) {
    $plugin =~ s/^X::/+App::NetdiscoX::Worker::Plugin::/;
    $plugin = 'App::Netdisco::Worker::Plugin::'. $plugin
      if $plugin !~ m/^\+/;
    $plugin =~ s/^\+//;

    $ENV{PLUGIN_LOAD_DEBUG} && debug "loading Netdisco plugin $plugin";
    eval { Module::Load::load $plugin };
  }
}

load_worker_plugins( setting('extra_worker_plugins') || [] );
load_worker_plugins( setting('worker_plugins') || [] );

true;
