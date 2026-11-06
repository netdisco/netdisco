#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

# Readers reload ACL Manager roles and groups only when the acl counter moves,
# so every ACL write route must run its writes inside acl_txn_do, which bumps
# the counter in the same transaction. A route that kept a bare txn_do would
# change the ACLs and leave every other process serving the old ones.
#
# acl_txn_do is replaced in each plugin's package by a recorder that does not
# run the block, so the test needs no database and pins only the route's use
# of the wrapper (the wrapper itself is covered by xt/179).

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco::Util::ManagedConfig 'acl_txn_do';
use App::Netdisco;
use App::Netdisco::Web;
use App::Netdisco::Web::Auth::Provider::DBIC;
use Dancer ':tests';
use Dancer::Test;

config->{logger} = 'null';

package FakeUser;
sub new      { return bless { username => $_[1] }, $_[0] }
sub username { return $_[0]->{username} }

# only the User updates and the name-exists check of ACLManager add run
# outside the wrapper
package FakeSchema;
sub new       { return bless {}, $_[0] }
sub resultset { return $_[0] }
sub search    { return $_[0] }
sub update    { return 1 }
sub count     { return 0 }

package main;

my $calls = 0;

no warnings 'redefine';
*App::Netdisco::Web::Auth::Provider::DBIC::get_user_details = sub {
  return FakeUser->new($_[1]);
};
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'someone' } };
*Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? ('admin') : ['admin'] };
*App::Netdisco::Web::Plugin::AdminTask::ACLManager::acl_txn_do = sub { ++$calls; return };
*App::Netdisco::Web::Plugin::AdminTask::ACLEditor::acl_txn_do  = sub { ++$calls; return };
*App::Netdisco::Web::Plugin::AdminTask::ACLManager::schema     = sub { return FakeSchema->new };

set trust_x_remote_user => 1;

# Dancer::Handler resets the cookie jar at the start of every request and
# Dancer::Test does not, so without this one request's session would
# authenticate the next.
sub send_route {
  my ($method, $path, %params) = @_;
  $calls = 0;
  Dancer::Cookies->init;
  # the ACLManager routes are ajax routes; Dancer::Test drops a dashed header
  # name (see xt/57), so the XHR marker goes in the environment
  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  return dancer_response($method => $path, {
    headers => [ 'X-REMOTE_USER' => 'someone' ],
    params  => { %params },
  });
}

my $res;

$res = send_route(POST => '/ajax/control/admin/aclmanager/add',
  acl_name => 'example', acl_type => 'host');
is $res->status, 200, 'aclRoutes__aclmanager_add__is_accepted';
is $calls, 1, 'aclRoutes__aclmanager_add__writes_inside_acl_txn_do';

$res = send_route(POST => '/ajax/control/admin/aclmanager/delete',
  acl_name => 'example');
is $res->status, 200, 'aclRoutes__aclmanager_delete__is_accepted';
is $calls, 1, 'aclRoutes__aclmanager_delete__writes_inside_acl_txn_do';

$res = send_route(POST => '/ajax/control/admin/aclmanager/update',
  acl_name => 'renamed', 'old-acl_name' => 'example', acl_type => 'host');
is $res->status, 200, 'aclRoutes__aclmanager_update__is_accepted';
is $calls, 1, 'aclRoutes__aclmanager_update__writes_inside_acl_txn_do';

$res = send_route(POST => '/ajax/control/admin/acleditor/add',
  acl_name => 'example', left_rule => '192.0.2.0/24');
is $res->status, 200, 'aclRoutes__acleditor_add__is_accepted';
is $calls, 1, 'aclRoutes__acleditor_add__writes_inside_acl_txn_do';

$res = send_route(POST => '/ajax/control/admin/acleditor/delete',
  id => 1, acl_name => 'example');
is $res->status, 200, 'aclRoutes__acleditor_delete__is_accepted';
is $calls, 1, 'aclRoutes__acleditor_delete__writes_inside_acl_txn_do';

$res = send_route(POST => '/ajax/control/admin/acleditor/update',
  id => 1, acl_name => 'example');
is $res->status, 200, 'aclRoutes__acleditor_update__is_accepted';
is $calls, 1, 'aclRoutes__acleditor_update__writes_inside_acl_txn_do';

done_testing;
