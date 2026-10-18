#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

# portctl_topology is documented as what allows port_control users to update
# the manual topology, but from #1060 it only hid the shortcut on the device
# ports view: the Manual Device Topology page and its routes still took any
# port_control user. That matters because /topology/del clears is_uplink on
# both ports, which then lets the portctl_uplinks guard pass for a real
# uplink, so the setting must switch the feature off at the routes.
#
# #1691 scopes the add and del routes to the user's port control role through
# _scope_ok. That is faked here to record that it was reached, so these tests
# see only the portctl_topology gate in front of it.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Web;
use Dancer ':tests';
use Dancer::Test;

config->{logger} = 'null';

package FakeSchema;
sub new       { return bless {}, $_[0] }
sub resultset { return $_[0] }
sub search    { return $_[0] }
sub next      { return undef }

package main;

my @roles;
my $scoped = 0;

no warnings 'redefine';
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'someone' } };
*Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? @roles : [@roles] };
*App::Netdisco::Web::Plugin::AdminTask::Topology::_scope_ok = sub { $scoped++; return 0 };
*App::Netdisco::Web::Plugin::AdminTask::Topology::schema    = sub { return FakeSchema->new };

set trust_x_remote_user => 1;

# Dancer::Handler resets the cookie jar at the start of every request and
# Dancer::Test does not, so without this one request's session would
# authenticate the next.
sub request_as {
  my ($method, $path, $params) = @_;
  $scoped = 0;
  Dancer::Cookies->init;
  # Dancer::Test drops a dashed name from its headers argument before the
  # request is built (see xt/57), so the XHR marker goes in the environment
  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  return dancer_response($method => $path, {
    headers => [ 'X-REMOTE_USER' => 'someone' ],
    params  => ($params || {}),
  });
}

my %link = (dev1 => '192.0.2.1', port1 => 'Gi1/1', dev2 => '192.0.2.2', port2 => 'Gi1/1');

foreach my $route (qw/add del/) {
  my $path = "/ajax/control/admin/topology/$route";

  @roles = ('port_control');
  setting('portctl_topology' => 0);
  my $res = request_as(POST => $path, \%link);
  is $res->status, 403, "topology_${route}__port_control_user_with_portctl_topology_off__is_refused";
  is $scoped, 0, "topology_${route}__port_control_user_with_portctl_topology_off__never_reaches_the_role_check";

  setting('portctl_topology' => 1);
  $res = request_as(POST => $path, \%link);
  ok $scoped, "topology_${route}__port_control_user_with_portctl_topology_on__goes_on_to_the_role_check";

  @roles = ('admin');
  setting('portctl_topology' => 0);
  $res = request_as(POST => $path, \%link);
  ok $scoped, "topology_${route}__admin_with_portctl_topology_off__goes_on_to_the_role_check";
}

@roles = ('port_control');
setting('portctl_topology' => 0);
my $res = request_as(GET => '/ajax/content/admin/topology');
is $res->status, 403, 'topology_content__port_control_user_with_portctl_topology_off__is_refused';

setting('portctl_topology' => 1);
$res = request_as(GET => '/ajax/content/admin/topology');
is $res->status, 200, 'topology_content__port_control_user_with_portctl_topology_on__is_served';

@roles = ('admin');
setting('portctl_topology' => 0);
$res = request_as(GET => '/ajax/content/admin/topology');
is $res->status, 200, 'topology_content__admin_with_portctl_topology_off__is_served';

# the page itself is registered once, from the setting as the web app loads,
# which here is the shipped default of off
@roles = ('port_control');
$res = request_as(GET => '/admin/topology');
isnt $res->status, 200, 'topology_page__port_control_user_with_the_default_portctl_topology__is_not_served';

@roles = ('admin');
$res = request_as(GET => '/admin/topology');
is $res->status, 200, 'topology_page__admin__is_served';

done_testing;
