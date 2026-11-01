#!/usr/bin/env perl

# sync_portctl_roles and its portctl_by_role_shadow copy used to rebuild the
# role list from the database on demand. The loader now puts ACL Manager roles
# in CONFIG at the start of every request and job, so a check only reads CONFIG.
# What is easy to get wrong when removing the old path:
# - check_acl used to create an empty host_groups entry for an unknown group,
#   which wrote into the global config on every read;
# - the role dropdown and the ACL delete both leaned on the shadow to tell
#   YAML roles from database roles, and now ask yaml_setting instead.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing'; }

use lib 'xt/lib';
use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;
use Test::Netdisco::ManagedACL qw(stub_managed_config);
use App::Netdisco::Util::ManagedConfig qw(capture_yaml_settings);
use App::Netdisco::Util::Permission 'check_acl';
use App::Netdisco::Util::Port ();
use App::Netdisco::Util::Configuration ();

# after the use lines, as Dancer switches warnings back on when imported
no warnings qw/once redefine/; # the glob overrides below are deliberate

my $IN = '192.0.2.1';

# the admin routes only need roles, so fake the user and its roles as xt/102 does
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'someone' } };
*Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? ('admin') : ['admin'] };
set trust_x_remote_user => 1;
config->{'portctl_by_role'} = { y => { 'group:somewhere' => ['192.0.2.50'] } };
capture_yaml_settings();

subtest 'removed__sync_portctl_roles_refresh_and_load_acls__are_gone' => sub {
  ok !App::Netdisco::Util::Port->can('sync_portctl_roles'), 'sync_portctl_roles';
  ok !App::Netdisco::Util::Configuration->can('refresh_managed_acl'), 'refresh_managed_acl';
  ok !App::Netdisco::Util::Configuration->can('load_acls_from_database'), 'load_acls_from_database';
};

subtest 'removed__no_portctl_by_role_shadow_in_config' => sub {
  ok !exists config->{'portctl_by_role_shadow'}, 'no shadow key';
};

subtest 'checkAcl__an_unknown_group__matches_nothing_and_is_not_written_into_config' => sub {
  ok !check_acl($IN, ['group:nosuch']), 'group:nosuch matches nothing';
  ok check_acl($IN, ['!group:nosuch']), '!group:nosuch matches';
  ok !exists setting('host_groups')->{'nosuch'}, 'host_groups is untouched';
};

subtest 'checkAcl__never_reads_the_database' => sub {
  my $calls = stub_managed_config(version => 1, rows => { netdisco => {
    office => { type => 'host', maps => [ [[$IN]] ] } } });
  check_acl($IN, ['group:office']) for 1 .. 5;
  check_acl($IN, ['group:nosuch']) for 1 .. 5;
  is $calls->{version_reads}, 0, 'counter not read';
  is $calls->{row_reads}, 0, 'rows not read';
};

# a recording stand-in for the schema: every call answers with itself, and the
# User updates are noted, so only the route logic above the database is real
{
  package FakeRS;
  our (@UPDATES, $LAST);
  sub new { return bless {}, shift }
  sub resultset { my ($s, $n) = @_; $LAST = undef; return $s }
  sub search { my ($s, $cond) = @_; $LAST = $cond; return $s }
  sub update { push @UPDATES, { cond => $LAST, set => $_[1] }; return 1 }
  sub hri { return $_[0] }
  sub all { return ({ username => 'someone', fullname => 'Some One' }) }
  sub host_acl_names { return () }
  sub AUTOLOAD { our $AUTOLOAD; return if $AUTOLOAD =~ /DESTROY$/; return $_[0] }
}

subtest 'users__role_dropdown__lists_yaml_and_database_roles_once' => sub {
  stub_managed_config(version => 1, rows => { netdisco => {
    d => { type => 'host_port', maps => [ [[$IN]] ] } } });
  *App::Netdisco::Web::Plugin::AdminTask::Users::schema = sub { FakeRS->new };

  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  my $res = dancer_response(GET => '/ajax/content/admin/users',
    { headers => [ 'X-REMOTE_USER' => 'someone' ] });
  is $res->status, 200, 'users list answers';
  # the page repeats the dropdown for each user row, so read the add form's
  my ($add) = $res->content =~ m{(data-form="add" name="port_control".*?</select>)}s;
  my @opts = ($add || '') =~ m{<option value="([^"]+)">Role: }g;
  is_deeply [sort @opts], [qw/d y/], 'each role is offered once';
};

subtest 'aclManagerDelete__a_role_also_in_yaml__keeps_users_on_it' => sub {
  *App::Netdisco::Web::Plugin::AdminTask::ACLManager::schema = sub { FakeRS->new };
  *App::Netdisco::Web::Plugin::AdminTask::ACLManager::acl_txn_do = sub { $_[0]->() };
  @FakeRS::UPDATES = ();

  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  my $res = dancer_response(POST => '/ajax/control/admin/aclmanager/delete',
    { headers => [ 'X-REMOTE_USER' => 'someone' ], params => { acl_name => 'y' } });
  is $res->status, 200, 'delete answers';
  my ($role) = grep { exists $_->{cond}->{portctl_role} } @FakeRS::UPDATES;
  ok $role, 'users on the role were updated';
  ok !exists $role->{set}->{portctl_role}, 'portctl_role is not cleared';
  ok !exists $role->{set}->{port_control}, 'port_control is not cleared';
};

done_testing;
