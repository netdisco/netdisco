#!/usr/bin/env perl

# node_wireless used to be cleared only as a side effect of deleting node rows
# for the same mac, so a client that stayed on the network kept every
# (mac, ssid) pair it ever held. The expire job now ages node_wireless out on
# its own time_last. There is no database in CI, so this runs the real expire
# worker against a schema stub that records which tables it deletes from and
# with what age.

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::Backend::Job;
use App::Netdisco::Worker::Plugin::Expire ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';
config->{enable_python_worklets} = 0; # the worker under test is Perl, and CI has no python venv to start

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

my @deletes;

package FakeRS;
sub new { my ($class, $name) = @_; return bless { name => $name }, $class }
sub search {
  my ($self, $cond) = @_;
  # the age is the single bind value of the time_last literal
  my $age = (ref $cond->{time_last} eq 'REF') ? ${ $cond->{time_last} }->[1] : undef;
  return bless { %$self, age => $age }, ref $self;
}
sub delete { my $self = shift; push @deletes, [$self->{name}, $self->{age}]; return 0 }

package FakeSchema;
sub new { return bless {}, shift }
sub txn_do { my ($self, $code) = @_; return $code->() }
sub resultset { return FakeRS->new($_[1]) }

package main;

{
  no warnings 'redefine';
  *App::Netdisco::Worker::Plugin::Expire::schema = sub { FakeSchema->new };
  *App::Netdisco::Worker::Plugin::Expire::update_stats = sub { 1 };
}

# only the settings under test decide what runs; everything else is off
sub run_expire {
  my %settings = @_;
  config->{$_} = 0 for qw/expire_devices expire_nodes expire_nodes_archive
                          expire_nodeip_orphans expire_jobs expire_userlog/;
  config->{expire_nodeip_freshness} = undef;
  config->{expire_node_wireless} = undef;
  config->{$_} = $settings{$_} for keys %settings;

  @deletes = ();
  my $job = App::Netdisco::Backend::Job->new({ job => 0, action => 'expire' });
  my $exception = '';
  try { MyWorker->new()->run($job) } catch { $exception = $_ };
  is $exception, '', 'no exception escapes run()';
  is $job->status, 'done', 'the expire job completes' or diag $job->log;
  return [ map { $_->[1] } grep { $_->[0] eq 'NodeWireless' } @deletes ];
}

subtest 'expire__node_wireless_unset__follows_expire_nodes' => sub {
  is_deeply run_expire(expire_nodes => 90), [90 * 86400],
    'node_wireless expires at the expire_nodes age';
};

subtest 'expire__node_wireless_set__uses_its_own_age' => sub {
  is_deeply run_expire(expire_nodes => 90, expire_node_wireless => 7), [7 * 86400],
    'expire_node_wireless overrides expire_nodes';
};

subtest 'expire__node_wireless_zero__leaves_node_wireless_alone' => sub {
  is_deeply run_expire(expire_nodes => 90, expire_node_wireless => 0), [],
    'zero turns node_wireless expiry off';
};

subtest 'expire__node_wireless_set_without_expire_nodes__still_expires' => sub {
  is_deeply run_expire(expire_node_wireless => 30), [30 * 86400],
    'node_wireless expiry does not depend on expire_nodes being on';
};

done_testing;
