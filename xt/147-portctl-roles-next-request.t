#!/usr/bin/env perl

# The port control routes used to call sync_portctl_roles() before their
# checks, and xt/93 checked the order of those calls in the source. The checks
# now load the ACL Manager roles themselves, at most once per request, so these
# tests change a role between two requests and check that the second sees it,
# with no sync anywhere: /ajax/portcontrol, the API's custom field jobs, and
# manual topology. Dancer clears vars for every request; keep_cache shows that
# is what drops the roles, not the stub.
#
# Only the database edges are faked: the user and its roles, the ACL Manager
# rows, the devices and ports, and the queue insert.

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; delete $ENV{ND2_DO_FORCE} }

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Web;
use App::Netdisco::Web::Auth::Provider::DBIC;
use Dancer ':tests';
use Dancer::Test;
use lib 'xt/lib';
use Test::Netdisco::ManagedACL 'stub_managed_acls';

config->{logger} = 'null';

package FakeUser;
sub new { my ($c, %a) = @_; return bless { username => 'someone', port_control => 1,
                                           admin => 0, portctl_role => 'leafonly', %a }, $c }
sub username     { $_[0]->{username} }
sub port_control { $_[0]->{port_control} }
sub admin        { $_[0]->{admin} }
sub portctl_role { $_[0]->{portctl_role} }

package FakePort;
sub new    { my ($c, %a) = @_; return bless {%a}, $c }
sub ip     { $_[0]->{ip} }
sub port   { $_[0]->{port} }
sub single { $_[0] }
sub update { $_[0] }

package FakePorts;
sub new    { my ($c, $ip) = @_; return bless { ip => $ip }, $c }
sub search { my ($s, $q) = @_;
             return FakePort->new(ip => $s->{ip}, port => ($q->{'me.port'} || $q->{port})) }

package FakeDevice;
sub new        { my ($c, $ip) = @_; return bless { ip => $ip }, $c }
sub ip         { $_[0]->{ip} }
sub in_storage { 1 }
sub ports      { FakePorts->new($_[0]->{ip}) }

package FakeSchema;
sub new       { return bless {}, $_[0] }
sub txn_do    { return $_[1]->() }
sub resultset { return $_[0] }
sub create    { return 1 }

package FakeUsersRS;
sub new    { my ($c, $rows) = @_; return bless { rows => $rows }, $c }
sub search { $_[0] }
sub hri    { $_[0] }
sub all    { @{ $_[0]->{rows} } }
sub host_acl_names      { () }
sub host_port_acl_names { die "the role list comes from portctl_roles() alone\n" }

package FakeUsersSchema;
sub new       { return bless {}, $_[0] }
sub resultset { my ($s, $name) = @_;
                return FakeUsersRS->new($name eq 'User'
                  ? [ { username => 'someone', fullname => 'Some One',
                        port_control => 1, portctl_role => 'dbrole' } ] : []) }

package FakeACLSchema;
our @updates;
sub new        { return bless {}, $_[0] }
sub txn_do     { return $_[1]->() }
sub resultset  { $_[0] }
sub search     { $_[0] }
sub find       { $_[0] }
sub update     { push @updates, $_[1]; return 1 }
sub delete     { return 1 }
sub left_acls  { () }
sub right_acls { () }

package main;

my $user  = FakeUser->new;
my @roles = ('port_control');

no warnings 'redefine';
*App::Netdisco::Web::Auth::Provider::DBIC::validate_api_token
  = sub { return ($_[1] eq 'goodtoken' ? $user : undef) };
*App::Netdisco::Web::Auth::Provider::DBIC::get_user_details = sub { return $user };
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return $user };
*Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? @roles : [@roles] };
*App::Netdisco::Web::PortControl::logged_in_user = sub { return $user };
*App::Netdisco::Web::API::Queue::logged_in_user  = sub { return $user };
*App::Netdisco::Web::Plugin::AdminTask::Topology::logged_in_user = sub { return $user };
*App::Netdisco::Web::PortControl::schema    = sub { return FakeSchema->new };
*App::Netdisco::Web::PortControl::jq_insert = sub { return 1 };
*App::Netdisco::Web::API::Queue::jq_insert  = sub { return 1 };
*App::Netdisco::Web::Plugin::AdminTask::Topology::schema     = sub { return FakeSchema->new };
*App::Netdisco::Web::Plugin::AdminTask::Topology::get_device = sub { return FakeDevice->new($_[0]) };
*App::Netdisco::Web::Plugin::AdminTask::Users::schema      = sub { return FakeUsersSchema->new };
*App::Netdisco::Web::Plugin::AdminTask::ACLManager::schema = sub { return FakeACLSchema->new };

setting('portctl_by_role' => {});
setting('portctl_topology' => 1);

# Dancer::Handler resets the cookie jar at the start of every request and
# Dancer::Test does not, so without this one request's session would
# authenticate the next.
sub web_request {
  my ($path, $params) = @_;
  Dancer::Cookies->init;
  set trust_x_remote_user => 1;
  # Dancer::Test drops a dashed name from its headers argument before the
  # request is built (see xt/57), so the XHR marker goes in the environment
  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  return dancer_response(POST => $path, {
    headers => [ 'X-REMOTE_USER' => 'someone' ], params => $params });
}

sub api_request {
  my $body = shift;
  Dancer::Cookies->init;
  # a trusted remote user header, absent here, would send the API to '/'
  set trust_x_remote_user => 0;
  return dancer_response(POST => '/api/v1/queue/jobs', {
    headers => [ 'Authorization' => 'goodtoken', 'Accept' => 'application/json',
                 'Content-Type' => 'application/json' ],
    body => $body });
}

sub web_get {
  my $path = shift;
  Dancer::Cookies->init;
  set trust_x_remote_user => 1;
  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  return dancer_response(GET => $path, { headers => [ 'X-REMOTE_USER' => 'someone' ] });
}

my %location = (device => '192.0.2.1', field => 'location', value => 'rack 4');
my %link     = (dev1 => '192.0.2.1', port1 => 'Gi1/1', dev2 => '192.0.2.2', port2 => 'Gi1/2');
my $cf_job   = '[{"action":"cf_owner","device":"192.0.2.1","subaction":"noc"}]';

my %covers = (both    => { leafonly => [ [['192.0.2.1', '192.0.2.2'], []] ] },
              neither => { leafonly => [ [['192.0.2.99'], []] ] });

subtest 'portcontrol__a_role_changed_between_requests__is_seen_by_the_next' => sub {
  @roles = ('port_control');
  stub_managed_acls($covers{both});
  is web_request('/ajax/portcontrol', \%location)->status, 200, 'the role covers the device';
  stub_managed_acls($covers{neither}, keep_cache => 1);
  is web_request('/ajax/portcontrol', \%location)->status, 403, 'the next request sees it no longer does';
};

subtest 'api__a_role_changed_between_requests__is_seen_by_the_next' => sub {
  @roles = ('api', 'port_control');
  stub_managed_acls($covers{both});
  is api_request($cf_job)->status, 200, 'the role covers the device';
  stub_managed_acls($covers{neither}, keep_cache => 1);
  is api_request($cf_job)->status, 403, 'the next request sees it no longer does';
};

subtest 'topology__a_role_changed_between_requests__is_seen_by_the_next' => sub {
  @roles = ('port_control');
  stub_managed_acls($covers{both});
  is web_request('/ajax/control/admin/topology/add', \%link)->status, 200, 'the role covers both ports';
  stub_managed_acls($covers{neither}, keep_cache => 1);
  is web_request('/ajax/control/admin/topology/add', \%link)->status, 403, 'the next request sees it no longer does';
};

subtest 'topology__checking_both_ports__loads_the_roles_once' => sub {
  @roles = ('port_control');
  my $calls = stub_managed_acls($covers{both});
  web_request('/ajax/control/admin/topology/add', \%link);
  is $$calls, 1, 'one load serves both port checks in the request';
};

subtest 'users__the_role_dropdown__lists_yaml_and_database_roles_from_portctl_roles' => sub {
  @roles = ('admin');
  setting('portctl_by_role' => { yamlrole => ['192.0.2.1'] });
  stub_managed_acls({ dbrole => [ [['192.0.2.1'], []] ] });

  my $res = web_get('/ajax/content/admin/users');
  is $res->status, 200, 'the page renders without asking for the ACL names again';
  like $res->content, qr/value="yamlrole"/, 'a YAML role is offered';
  like $res->content, qr/value="dbrole"/,   'and a database role';

  setting('portctl_by_role' => {});
};

subtest 'aclmanager__deleting_a_role_yaml_also_defines__leaves_its_users_their_role' => sub {
  @roles = ('admin');
  # set after the app loaded, which the old load-time backup never saw
  setting('portctl_by_role' => { yamlrole => ['192.0.2.1'] });

  @FakeACLSchema::updates = ();
  web_request('/ajax/control/admin/aclmanager/delete', { acl_name => 'yamlrole' });
  is_deeply $FakeACLSchema::updates[0], {}, 'users keep a role YAML still defines';

  @FakeACLSchema::updates = ();
  web_request('/ajax/control/admin/aclmanager/delete', { acl_name => 'dbonly' });
  ok exists $FakeACLSchema::updates[0]->{portctl_role},
    'a role only the database defined is taken from its users';

  setting('portctl_by_role' => {});
};

done_testing;
