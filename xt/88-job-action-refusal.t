#!/usr/bin/env perl

# A job's action names the worker the backend will run. Some workers are meant
# to be reached only with netdisco-do on the host, and the route loop in
# AdminTask already declines to publish a route for the hook namespace. Two
# paths took an action from a request anyway and bypassed that: the queue API,
# and add_job, which the Discover form reaches with a request parameter.
#
# add_job is exercised with the queue insert overridden, so a refusal is
# distinguishable from a job queued and then failing for want of a database.

use strict;
use warnings;
no warnings 'once'; # the jq_insert override below is single-use by design

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing' }

use Test::More 0.88;
use File::Slurper 'read_text';
use App::Netdisco;
use App::Netdisco::Util::JobAction 'action_is_refused';
use App::Netdisco::Web::AdminTask;

my @queued;
{
  no warnings 'redefine';
  *App::Netdisco::Web::AdminTask::jq_insert = sub { push @queued, $_[0]; return 1 };
}

sub queued_for {
  my $action = shift;
  @queued = ();
  eval { App::Netdisco::Web::AdminTask::add_job($action, undef) };
  return scalar @queued;
}

subtest 'actionIsRefused__a_refused_worker__returns_true' => sub {
  ok action_is_refused($_), "$_ is refused" for qw/
    hook scheduler psql getapikey dumpconfig dumpinfocache show
  /;
  ok action_is_refused('hook::exec'), 'a namespace under a refused action is refused';
  ok action_is_refused('HOOK'),       'the check is case insensitive';
};

subtest 'actionIsRefused__a_shipped_action__returns_false' => sub {
  ok !action_is_refused($_), "$_ is permitted" for qw/
    discover arpnip macsuck nbtstat portcontrol location contact snapshot
    loadmibs delete cf_myfield
  /;
};

subtest 'actionIsRefused__nothing_usable__returns_false_without_dying' => sub {
  my @junk = (undef, '', ' ', 0, [], {});
  foreach my $input (@junk) {
    my $got = eval { action_is_refused($input) };
    ok !$@, 'no exception on an unusable action';
    ok !$got, 'an unusable action is not treated as refused';
  }
};

subtest 'addJob__a_refused_action__never_reaches_the_queue' => sub {
  is queued_for($_), 0, "$_ is not queued" for qw/hook::exec scheduler psql show/;
};

subtest 'addJob__a_permitted_action__still_reaches_the_queue' => sub {
  is queued_for('discover'), 1, 'discover is queued as before';
  is $queued[0][0]{action}, 'discover', 'and carries its own action';
};

subtest 'apiQueue__the_refusal__is_applied_before_the_insert' => sub {
  # an import satisfies a search for either sub name on its own, so both of
  # these look for the call rather than the symbol
  my $src = read_text('lib/App/Netdisco/Web/API/Queue.pm');
  my $guard  = index $src, 'action_is_refused($job->{action})';
  my $insert = index $src, 'jq_insert($jobs)';
  cmp_ok $guard, '>', -1, 'the submitted action is put to the refusal';
  cmp_ok $insert, '>', -1, 'and the route still inserts';
  cmp_ok $guard, '<', $insert, 'the refusal comes first';
};

done_testing;
