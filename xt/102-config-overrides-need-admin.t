#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

# A job's port and subaction may carry configuration overrides, which the job
# applies before it runs. Only an admin may set configuration, so the two
# routes open to port_control users refuse any job that carries overrides.
#
# Only the DB edges are faked: the user, its roles, the device role check,
# the port log row and the queue insert. The routes, the role checks and the
# parser are the real ones.

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Web;
use App::Netdisco::Web::Auth::Provider::DBIC;
use App::Netdisco::Backend::Job;
use App::Netdisco::Util::Configuration 'split_params_to_config';
use MIME::Base64 'encode_base64';
use JSON::PP ();
use Dancer ':tests';
use Dancer::Test;

config->{logger} = 'null';

my $override = '{"value":"Gi1/0/1","with":{"snmptimeout":true}}';

# split_params_to_config

{
  my $before = setting('snmptimeout');
  my ($value, $overrides) = split_params_to_config($override);
  is $value, 'Gi1/0/1',
    'split_params_to_config__value_with_overrides__returns_the_value';
  is_deeply [keys %{ $overrides || {} }], ['snmptimeout'],
    'split_params_to_config__value_with_overrides__returns_the_overrides';
  is setting('snmptimeout'), $before,
    'split_params_to_config__value_with_overrides__leaves_configuration_alone';

  my ($plain, $none) = split_params_to_config('Gi1/0/1');
  is $plain, 'Gi1/0/1',
    'split_params_to_config__plain_value__returns_it_unchanged';
  ok !$none, 'split_params_to_config__plain_value__returns_no_overrides';
}

# carries_config_overrides

sub carries { App::Netdisco::Backend::Job->carries_config_overrides({@_}) }

ok carries(action => 'portcontrol', port => $override),
  'carries_config_overrides__override_in_port__is_true';
ok carries(action => 'portcontrol', port => 'Gi1/0/1', subaction => $override),
  'carries_config_overrides__override_in_subaction__is_true';
ok !carries(action => 'portcontrol', port => 'GigabitEthernet1/0/1',
            subaction => 'up'),
  'carries_config_overrides__plain_port_and_status__is_false';
ok !carries(action => 'portname', port => 'Port 1.2',
            subaction => 'uplink to core'),
  'carries_config_overrides__port_name_with_spaces__is_false';
ok carries(action => 'portcontrol', port => 'Gi1/0/1',
           subaction => 'snmptimeout=1-other'),
  'carries_config_overrides__key_value_form_in_subaction__is_true';
ok carries(action => 'portname', port => 'Gi1/0/1',
           subaction => encode_base64('{"snmptimeout":true}', '')),
  'carries_config_overrides__base64_override_in_subaction__is_true';
ok carries(action => 'discover', extra => '{"with":{"snmptimeout":1}}'),
  'carries_config_overrides__override_in_extra__is_true';
ok carries(action => 'cf_owner', port => $override),
  'carries_config_overrides__override_in_port_of_custom_field_job__is_true';
ok !carries(action => 'cf_owner', port => 'Gi1/0/1',
            subaction => '{"with":{"snmptimeout":true}}'),
  'carries_config_overrides__subaction_of_custom_field_job__is_false';

foreach my $plain ('down-other', 'bounce-other', 'core uplink', '') {
  ok !carries(action => 'portcontrol', port => 'Gi1/0/1', subaction => $plain),
    "carries_config_overrides__plain_value_'${plain}'__is_false";
}

# the routes

package FakeUser;
sub new      { return bless { username => $_[1] }, $_[0] }
sub username { return $_[0]->{username} }

package FakeSchema;
sub new       { return bless {}, $_[0] }
sub txn_do    { return $_[1]->() }
sub resultset { return $_[0] }
sub create    { return 1 }

package main;

my @roles;
my @queued;

no warnings 'redefine';
*App::Netdisco::Web::Auth::Provider::DBIC::validate_api_token = sub {
  return ($_[1] eq 'goodtoken' ? FakeUser->new('apiuser') : undef);
};
*App::Netdisco::Web::Auth::Provider::DBIC::get_user_details = sub {
  return FakeUser->new($_[1]);
};
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'someone' } };
*Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? @roles : [@roles] };
*App::Netdisco::Web::PortControl::schema    = sub { return FakeSchema->new };
# the device role check passes, so only the override check can refuse
*App::Netdisco::Web::PortControl::sync_portctl_roles       = sub { return };
*App::Netdisco::Web::PortControl::device_acl_by_role_check = sub { return 1 };
*App::Netdisco::Web::PortControl::jq_insert = sub { push @queued, @_; return 1 };
*App::Netdisco::Web::API::Queue::jq_insert  = sub { push @queued, @{$_[0]}; return 1 };

set trust_x_remote_user => 1;

# Dancer::Handler resets the cookie jar at the start of every request and
# Dancer::Test does not, so without this one request's session would
# authenticate the next.
sub fresh_request { Dancer::Cookies->init; return dancer_response(@_) }

sub portcontrol {
  my %params = @_;
  @queued = ();
  # Dancer::Test drops a dashed name from its headers argument before the
  # request is built (see xt/57), so the XHR marker goes in the environment
  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  return fresh_request(POST => '/ajax/portcontrol', {
    headers => [ 'X-REMOTE_USER' => 'someone' ],
    params  => { device => '192.0.2.1', field => 'c_port',
                 action => 'down', %params },
  });
}

sub queue_jobs {
  my $jobs = shift;
  @queued = ();
  return fresh_request(POST => '/api/v1/queue/jobs', {
    headers => [ 'Authorization' => 'goodtoken',
                 'Accept' => 'application/json',
                 'Content-Type' => 'application/json' ],
    body    => $jobs,
  });
}

@roles = ('port_control');

my $res = portcontrol(port => $override);
is $res->status, 403,
  'portcontrol__port_control_user_sends_override_in_port__is_refused';
is scalar @queued, 0,
  'portcontrol__port_control_user_sends_override__queues_nothing';

$res = portcontrol(port => 'Gi1/0/1', action => 'snmptimeout=1');
is $res->status, 403,
  'portcontrol__port_control_user_sends_override_in_action__is_refused';
is scalar @queued, 0,
  'portcontrol__port_control_user_sends_override_in_action__queues_nothing';

$res = portcontrol(port => 'Gi1/0/1');
is $res->status, 200, 'portcontrol__port_control_user_sends_plain_port__is_accepted';
is scalar @queued, 1, 'portcontrol__port_control_user_sends_plain_port__queues_the_job';

@roles = ('admin', 'port_control');

$res = portcontrol(port => $override);
is $res->status, 200, 'portcontrol__admin_sends_override__is_accepted';
is scalar @queued, 1, 'portcontrol__admin_sends_override__queues_the_job';

# a trusted remote user header, absent here, would send the API to '/'
set trust_x_remote_user => 0;
@roles = ('api', 'port_control');

$res = queue_jobs(qq{[{"action":"cf_owner","device":"192.0.2.1","port":${\ JSON::PP->new->encode($override)}}]});
is $res->status, 403,
  'queue_jobs__port_control_user_sends_override_in_custom_field_port__is_refused';
like $res->content, qr/configuration overrides/i,
  'queue_jobs__port_control_user_sends_override__says_why';
is scalar @queued, 0, 'queue_jobs__port_control_user_sends_override__queues_nothing';

@roles = ('api', 'api_admin');

$res = queue_jobs(qq{[{"action":"discover","device":"192.0.2.1","extra":"snmptimeout=1"}]});
is $res->status, 200, 'queue_jobs__api_admin_sends_override__is_accepted';
is scalar @queued, 1, 'queue_jobs__api_admin_sends_override__queues_the_job';

done_testing;
