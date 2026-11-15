#!/usr/bin/env perl

# The backend manager decides which devices to skip before any job starts:
# jq_getsome runs get_denied_actions, which checks discover_only and the other
# device ACL settings. Those can name an ACL Manager host ACL as
# group:<name>, so the manager loads the ACL Manager config too, on each pass
# of its loop. Without it the group was unknown there, matched nothing, and
# the manager skiplisted every device that a poller would have allowed.
#
# Only the two database reads and the job queue are stubbed; the manager loop
# and the loader are real.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use lib 'xt/lib';
use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;

# the manager imports jq_getsome when it compiles and namespace::clean then
# drops the name, so a later glob override never reaches its call: give it a
# dispatcher to import instead
our $JQ_GETSOME;
BEGIN {
  require App::Netdisco::JobQueue;
  no warnings 'redefine';
  *App::Netdisco::JobQueue::jq_getsome = sub { $JQ_GETSOME->(@_) };
}
use App::Netdisco::Backend::Role::Manager;
use App::Netdisco::Util::ManagedConfig qw/capture_yaml_settings/;
use App::Netdisco::Util::Permission qw/check_acl/;
use Test::Netdisco::ManagedACL qw/stub_managed_config/;
use Dancer qw/:script !pass/;

config->{logger} = 'null';
config->{workers} = { %{ setting('workers') || {} }, no_manager => 0, sleep_time => 0 };
capture_yaml_settings();

{ package FakeQueue;
  sub new     { return bless {}, shift }
  sub pending { return 0 } }

{ package FakeManager;
  use Role::Tiny::With;
  with 'App::Netdisco::Backend::Role::Manager';
  sub new { return bless { queues => [ { name => 'q', tasks => 1, queue => FakeQueue->new } ] }, shift }
  sub wid { return 1 } }

my $IN = '192.0.2.1';

# what the manager's checks see when it asks the job queue for work; then
# leave the endless loop
sub manager_sees {
  my $seen;
  local $JQ_GETSOME = sub {
    $seen = check_acl($IN, ['group:lab']) ? 1 : 0;
    die "stop\n";
  };
  eval { FakeManager->new->worker_body };
  is($@, "stop\n", 'the manager reached the job queue');
  return $seen;
}

subtest 'manager__checks_see_an_acl_manager_named_group' => sub {
  stub_managed_config(version => 1, rows => { netdisco => {
    lab => { type => 'host', maps => [ [[$IN]] ] } } });
  is(manager_sees(), 1, 'group:lab matches its row');
};

subtest 'manager__reloads_when_the_counter_moves' => sub {
  stub_managed_config(version => 1, rows => { netdisco => {
    lab => { type => 'host', maps => [ [[$IN]] ] } } });
  is(manager_sees(), 1, 'group:lab matches');

  stub_managed_config(version => 2, keep_cache => 1, rows => { netdisco => {} });
  is(manager_sees(), 0, 'the deleted ACL is gone on the next pass');
};

done_testing;
