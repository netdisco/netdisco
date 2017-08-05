package App::Netdisco::Backend::Util;

use strict;
use warnings;

use Dancer ':syntax';

# load core worker plugins for our workers
# NOTE: this package is loaded for all actions whether backend or netdisco-do

use Module::Load ();

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

# support utilities for Backend Actions

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ job_done job_error job_defer /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub job_done  { return ('done',  shift) }
sub job_error { return ('error', shift) }
sub job_defer { return ('defer', shift) }

1;
