#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

# A port_control user may update custom fields through the API, but the
# custom field is written straight to the device row as the job is queued,
# with no worker check phase to scope it. From #1691 the web route for the
# same edit (/ajax/portcontrol) refuses a device outside the user's port
# control role, so the API must make the same device check or a scoped user
# could write custom fields on any device by calling it instead.
#
# Only the DB edges are faked: the user, its roles, the role sync and the
# queue insert. The route, the role checks and the device check are the real
# ones.

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
sub new { my ($c, %a) = @_; return bless { username => 'someone', port_control => 1, admin => 0, portctl_role => '', %a }, $c }
sub username     { $_[0]->{username} }
sub port_control { $_[0]->{port_control} }
sub admin        { $_[0]->{admin} }
sub portctl_role { $_[0]->{portctl_role} }

package main;

my @roles;
my @queued;
my $user;

no warnings 'redefine';
*App::Netdisco::Web::Auth::Provider::DBIC::validate_api_token = sub {
  return ($_[1] eq 'goodtoken' ? $user : undef);
};
*App::Netdisco::Web::Auth::Provider::DBIC::get_user_details = sub { return $user };
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return $user };
*App::Netdisco::Web::API::Queue::logged_in_user   = sub { return $user };
*Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? @roles : [@roles] };
*App::Netdisco::Web::API::Queue::jq_insert = sub { push @queued, @{$_[0]}; return 1 };

setting('portctl_by_role' => { leafonly => ['192.0.2.1'] });
stub_managed_acls({});

# Dancer::Handler resets the cookie jar at the start of every request and
# Dancer::Test does not, so without this one request's session would
# authenticate the next.
sub queue_jobs {
  my $jobs = shift;
  @queued = ();
  Dancer::Cookies->init;
  return dancer_response(POST => '/api/v1/queue/jobs', {
    headers => [ 'Authorization' => 'goodtoken',
                 'Accept' => 'application/json',
                 'Content-Type' => 'application/json' ],
    body    => $jobs,
  });
}

my $IN  = '{"action":"cf_owner","device":"192.0.2.1","subaction":"noc"}';
my $OUT = '{"action":"cf_owner","device":"192.0.2.99","subaction":"noc"}';

@roles = ('api', 'port_control');
$user  = FakeUser->new(portctl_role => 'leafonly');

my $res = queue_jobs("[$IN]");
is $res->status, 200, 'queue_jobs__scoped_user_on_a_device_in_the_role__is_accepted';
is scalar @queued, 1, 'queue_jobs__scoped_user_on_a_device_in_the_role__queues_the_job';

$res = queue_jobs("[$OUT]");
is $res->status, 403, 'queue_jobs__scoped_user_on_a_device_outside_the_role__is_refused';
is scalar @queued, 0, 'queue_jobs__scoped_user_on_a_device_outside_the_role__queues_nothing';

$res = queue_jobs("[$IN,$OUT]");
is $res->status, 403, 'queue_jobs__scoped_user_with_one_device_outside_the_role__is_refused';
is scalar @queued, 0, 'queue_jobs__scoped_user_with_one_device_outside_the_role__queues_none_of_them';

$res = queue_jobs('[{"action":"cf_owner","subaction":"noc"}]');
is $res->status, 403, 'queue_jobs__scoped_user_with_no_device__is_refused';
is scalar @queued, 0, 'queue_jobs__scoped_user_with_no_device__queues_nothing';

$user = FakeUser->new(portctl_role => 'nosuchrole');
$res = queue_jobs("[$IN]");
is $res->status, 403, 'queue_jobs__user_with_an_unknown_role__is_refused';

$user = FakeUser->new;
$res = queue_jobs("[$OUT]");
is $res->status, 200, 'queue_jobs__any_port_user__is_accepted_on_any_device';

# as on the web route, an admin is not scoped by a port control role
@roles = ('api', 'api_admin', 'port_control');
$user  = FakeUser->new(admin => 1, portctl_role => 'leafonly');
$res = queue_jobs("[$OUT]");
is $res->status, 200, 'queue_jobs__api_admin__is_not_scoped_by_the_role';

done_testing;
