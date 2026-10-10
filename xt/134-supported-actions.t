#!/usr/bin/env perl

# The list of actions a backend (and netdisco-do --list) knows is derived from
# the configured worker plugins alone, without loading them. An action
# implemented only by a python worklet is still run by the worker loader, so it
# must be listed too. Stages are the first sub-namespace of an action, and a
# python worklet's phase (main, early, ...) is never mistaken for one.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';

use App::Netdisco::Worker::Actions qw/supported_actions supported_stages/;

sub configure {
  my %conf = @_;
  config->{$_} = $conf{$_} for qw/worker_plugins extra_worker_plugins
    enable_python_worklets python_worker_plugins extra_python_worker_plugins/;
}

sub supported_with {
  configure(@_);
  return [ sort @{ supported_actions() } ];
}

my %none = (
  worker_plugins => [], extra_worker_plugins => [], enable_python_worklets => 1,
  python_worker_plugins => [], extra_python_worker_plugins => [],
);

subtest 'supportedActions__plugins__are_distinct_lowercased_actions_without_internal' => sub {
  is_deeply supported_with(%none,
      worker_plugins => [qw/Internal::BackendFQDN Discover Discover::Hooks
                            Macsuck::Nodes DiscoverAll/],
      extra_worker_plugins => ['X::MySite'],
    ), [qw/discover discoverall macsuck mysite/],
    'plugin namespaces collapse to one lowercase action each';
};

subtest 'supportedActions__worklet_only_action__is_supported_when_python_is_enabled' => sub {
  my %py = (
    worker_plugins => ['Discover'],
    python_worker_plugins => [ 'discover.main', { 'linter.main.cli' => { only => 'x' } } ],
    extra_python_worker_plugins => ['Site.late'],
  );

  is_deeply supported_with(%none, %py), [qw/discover linter site/],
    'bare and hash entries both name an action, extra worklets included';

  is_deeply supported_with(%none, %py, enable_python_worklets => 0), ['discover'],
    'worklets are ignored when python is disabled, as the loader ignores them';
};

subtest 'supportedStages__perl_and_worklets__are_first_namespace_never_a_phase' => sub {
  configure(%none,
    worker_plugins => [qw/Internal::BackendFQDN Discover Discover::Neighbors
                          Discover::Neighbors::DOCSIS Discover::VLANs Expire/],
    extra_worker_plugins => ['X::MySite::Audit'],
    python_worker_plugins => [ 'discover.nexthopneighbors.main.cli',
                               { 'arpnip.subnets.main.snmp' => { only => 'x' } },
                               'linter.main', 'stats.early' ],
  );

  is_deeply supported_stages(), {
    discover => [qw/neighbors nexthopneighbors vlans/],
    mysite   => ['audit'],
    arpnip   => ['subnets'],
  }, 'sub-namespaces are merged, sorted and de-duplicated; actions without stages are absent';

  configure(%none, python_worker_plugins => ['discover.nexthopneighbors.main'],
            enable_python_worklets => 0);
  is_deeply supported_stages(), {}, 'worklet stages are ignored when python is disabled';
};

done_testing;
