package App::Netdisco::Backend;

use strict;
use warnings;

use Module::Load ();
use Dancer ':syntax';

# load core worker plugins for our workers
# NOTE: this package is loaded for all actions whether backend or netdisco-do

sub load_core_plugins {
  my $plugin_list = shift;

  foreach my $plugin (@$plugin_list) {
    $plugin =~ s/^X::/+App::NetdiscoX::Core::Plugin::/;
    $plugin = 'App::Netdisco::Core::Plugin::'. $plugin
      if $plugin !~ m/^\+/;
    $plugin =~ s/^\+//;

    debug "loading Netdisco plugin $plugin";
    eval { Module::Load::load $plugin };
  }
}

load_core_plugins( setting('extra_core_plugins') || [] );
load_core_plugins( setting('core_plugins') || [] );

true;
