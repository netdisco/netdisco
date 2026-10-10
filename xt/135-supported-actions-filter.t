#!/usr/bin/env perl

# A backend only asks for jobs of actions it has a worker plugin for. That list
# is a single bind value, and DBIC reads any two element arrayref in bind as
# [ column, value ], so a backend supporting exactly two actions lost the first
# and never ran its jobs. job_prio.high is bound the same way. No database is
# needed, only the bind values DBIC resolves.
#
# An action implemented only by a python worklet is still run by the worker
# loader, so its jobs must not be filtered out either.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use Dancer qw/:moose :script !pass/;

# loaded lazily by DBIC, which would replace the next() stub below if it came later
use DBIx::Class::ResultSet ();

config->{logger} = 'null';
setting('workers')->{'BACKEND'} = 'test-backend';

require App::Netdisco::JobQueue::PostgreSQL;

sub supported_with {
  my %conf = @_;
  config->{$_} = $conf{$_} for qw/worker_plugins extra_worker_plugins
    enable_python_worklets python_worker_plugins extra_python_worker_plugins/;
  return [ sort @{ App::Netdisco::JobQueue::PostgreSQL::_compute_supported_actions() } ];
}

my %none = (
  worker_plugins => [], extra_worker_plugins => [], enable_python_worklets => 1,
  python_worker_plugins => [], extra_python_worker_plugins => [],
);

subtest 'computeSupportedActions__plugins__are_distinct_lowercased_actions_without_internal' => sub {
  is_deeply supported_with(%none,
      worker_plugins => [qw/Internal::BackendFQDN Discover Discover::Hooks
                            Macsuck::Nodes DiscoverAll/],
      extra_worker_plugins => ['X::MySite'],
    ), [qw/discover discoverall macsuck mysite/],
    'plugin namespaces collapse to one lowercase action each';
};

subtest 'computeSupportedActions__worklet_only_action__is_supported_when_python_is_enabled' => sub {
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

subtest 'getsome__exactly_two_supported_actions__binds_them_both_as_one_array' => sub {
  supported_with(%none, worker_plugins => [qw/Discover Macsuck Macsuck::Nodes/]);
  config->{job_prio}->{high} = [qw/snapshot vlan/];

  my @query;
  {
    no warnings 'redefine';
    local *DBIx::Class::ResultSet::next = sub { push @query, ${ $_[0]->as_query }; return };
    App::Netdisco::JobQueue::PostgreSQL::jq_getsome(1);
  }
  my ($sql, @bind) = @{ $query[0] };

  is scalar @bind, 7, 'every placeholder in the view has a bind value';
  is $bind[0]->[1], 'test-backend', 'the backend is bound ahead of the actions';
  is_deeply $bind[1]->[1], [qw/discover macsuck/],
    'both actions arrive as one array, not as [ column, value ]';
  is_deeply $bind[2]->[1], [qw/snapshot vlan/],
    'a two entry job_prio.high is bound the same way';
};

done_testing;
