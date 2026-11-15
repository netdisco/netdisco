#!/usr/bin/env perl

# Deleting a database role in the ACL Manager removes it from every user, and
# turns port control off for a user left with no role. An empty role list
# with port_control on reads as "Enabled (any port)" in the role checks, so a
# user must never be left holding {}.
#
# The last-role match once compared with equality (portctl_roles = ARRAY[?]),
# which missed a user holding the name twice. A rename onto an existing name
# left such users (it renamed users before the ACL rename failed), and
# array_remove then gave them {} with port_control on: every port. The
# containment match (<@) needs PostgreSQL's array semantics, so this runs the
# delete route against a real database; xt/222 pins the condition in CI.
#
# No DANCER_ENVDIR=/dev/null here, unlike most neighbours: that empties the
# DSN, and this file needs a real one. Nothing it writes survives: users is
# shadowed by a temporary table of the same shape, ACL Manager tables are not
# touched (acl_txn_do is stubbed), and the whole test is rolled back.

use strict;
use warnings;

use lib 'xt/lib';
use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::ManagedConfig qw(capture_yaml_settings);

# after the use lines, as Dancer switches warnings back on when imported
no warnings qw/once redefine/; # the glob overrides below are deliberate

config->{logger} = 'null';
setting('no_auth' => 1);
set trust_x_remote_user => 1;
config->{'portctl_by_role'} = {};
capture_yaml_settings();

my $schema = eval {
  my $s = schema('netdisco');
  $s->storage->dbh_do(sub { $_[1]->do('SELECT 1 FROM users LIMIT 1') });
  $s;
};
my $why = $@;

# The skip reason is always printed: a silent skip would leave this file
# green while proving nothing.
SKIP: {
  skip "no usable netdisco database: $why", 1 if not $schema;

  my $dbh = $schema->storage->dbh;
  $schema->txn_begin;

  # pg_temp is searched before the real schema, so the route's unqualified
  # "users" is this table for the rest of the session. It keeps the real
  # table's columns, so anything else that reads users still works, and
  # gains portctl_roles on a database not yet upgraded.
  $dbh->do('SET LOCAL client_min_messages = warning');
  $dbh->do('CREATE TEMP TABLE users (LIKE users INCLUDING DEFAULTS)');
  $dbh->do('ALTER TABLE pg_temp.users ADD COLUMN IF NOT EXISTS portctl_roles text[]');

  my %seed = (
    twice   => '{gone,gone}',
    empty   => '{}',
    only    => '{gone}',
    shared  => '{gone,kept}',
    other   => '{kept}',
    anyport => undef,
  );
  $dbh->do('INSERT INTO pg_temp.users (username, port_control, portctl_roles) VALUES (?, true, ?)',
    undef, $_, $seed{$_}) for sort keys %seed;

  local *Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'someone' } };
  local *Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? ('admin') : ['admin'] };
  local *App::Netdisco::Web::Plugin::AdminTask::ACLManager::acl_txn_do = sub { return };
  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';

  my $res = dancer_response(POST => '/ajax/control/admin/aclmanager/delete',
    { headers => [ 'X-REMOTE_USER' => 'someone' ], params => { acl_name => 'gone' } });

  my %after = map { $_->[0] => { port_control => $_->[1], roles => $_->[2] } }
    @{ $dbh->selectall_arrayref(
      'SELECT username, port_control, portctl_roles FROM pg_temp.users') };

  $schema->txn_rollback;

  subtest 'aclManagerDelete__last_role__users_left_without_a_role_are_turned_off' => sub {
    is $res->status, 200, 'delete answers';

    foreach my $user (qw/twice only empty/) {
      ok !$after{$user}{port_control}, "$user: port control off";
      is $after{$user}{roles}, undef, "$user: no roles";
    }

    ok $after{shared}{port_control}, 'shared: keeps port control';
    is_deeply $after{shared}{roles}, ['kept'], 'shared: keeps its other role';

    ok $after{other}{port_control}, 'other: untouched';
    is_deeply $after{other}{roles}, ['kept'], 'other: role untouched';

    ok $after{anyport}{port_control}, 'anyport: still any port';
    is $after{anyport}{roles}, undef, 'anyport: still no roles';
  };
}

done_testing;
