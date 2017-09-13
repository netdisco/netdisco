package App::Netdisco::Worker;

use strict;
use warnings;

use Module::Load ();
use Module::Find 'findallmod';
use Dancer ':syntax';

# load worker plugins for our action

sub import {
  my ($class, $action) = @_;
  die "missing action\n" unless $action;

  my @user_plugins = @{ setting('extra_worker_plugins') || [] };
  my @core_plugins = findallmod 'App::Netdisco::Worker::Plugin';

  foreach my $plugin (@user_plugins, @core_plugins) {
    $plugin =~ s/^X::/App::NetdiscoX::Worker::Plugin::/;
    next unless $plugin =~ m/::Plugin::${action}(?:::|$)/i;

    debug "loading worker plugin $plugin";
    Module::Load::load $plugin;
  }
}

true;
