#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::DB; # fake user row
use App::Netdisco::Web::Auth::Provider::DBIC;

use Dancer qw/:script !pass/;

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# API token auth now restricts by a *managed ACL name* (users.token_acl,
# referencing access_control_list_name) instead of the old
# users.token_allowed_ips text[] column. validate_api_token() loads the
# named ACL's mappings (prefetched alongside the user row), synthesizes
# them into config->{host_groups} via refresh_managed_acl(), then checks
# the requesting client IP against that host group with acl_matches_only()
# - all real, unmocked App::Netdisco::Util::{Configuration,Permission}
# code. What's faked here is only the DB access: a fake schema/resultset
# stands in for Dancer::Plugin::DBIC's schema(), and fake ACL result
# objects stand in for the AccessControlListName/Map/List rows that would
# normally be prefetched from Postgres (unavailable to xt/ tests). This
# mirrors the fake-the-DB-edges approach in xt/51-updated-device-hook.t.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

package FakeAccessControlList; # stands in for a fetched AccessControlList row
sub new { my ($class, %v) = @_; return bless {%v}, $class; }
sub id    { return $_[0]->{id} }
sub rules { return $_[0]->{rules} }

package FakeAccessControlListMap; # stands in for a fetched AccessControlListMap row
sub new { my ($class, %v) = @_; return bless {%v}, $class; }
sub id        { return $_[0]->{id} }
sub left_acl  { return $_[0]->{left_acl} }
sub right_acl { return $_[0]->{right_acl} }

package FakeMappingsRS; # stands in for the prefetched ->mappings relation
sub new { my ($class, @rows) = @_; return bless { rows => [@rows] }, $class; }
sub all { return @{ $_[0]->{rows} } }

package FakeAccessControlListName; # stands in for a fetched AccessControlListName row
sub new { my ($class, %v) = @_; return bless {%v}, $class; }
sub acl_name { return $_[0]->{acl_name} }
sub acl_type { return $_[0]->{acl_type} }
sub mappings { return FakeMappingsRS->new(@{ $_[0]->{mappings} }) }

package FakeUserRS; # only find() is used, standing in for a prefetching find
sub new  { my ($class, $row) = @_; return bless { row => $row }, $class; }
sub find {
  my ($self, $cond) = @_;
  return undef unless $cond->{token} eq $self->{row}->token;
  return $self->{row};
}

package FakeSchema; # stands in for the Dancer::Plugin::DBIC schema() handle
sub new        { my ($class, $row) = @_; return bless { row => $row }, $class; }
sub resultset  { return FakeUserRS->new($_[0]->{row}) }

package FakeRequest; # stands in for the Dancer request object
sub new            { my ($class, $ip) = @_; return bless { ip => $ip }, $class; }
sub remote_address { return $_[0]->{ip} }

package main;

# a managed "host" ACL naming one allowed source network, as the ACL
# manager UI would create it (App::Netdisco::Util::Configuration::
# refresh_managed_acl turns this into config->{host_groups})
my $allowed_net = FakeAccessControlList->new(id => 1, rules => ['192.0.2.0/24']);
my $map         = FakeAccessControlListMap->new(id => 1, left_acl => $allowed_net, right_acl => undef);
my $token_acl   = FakeAccessControlListName->new(
  acl_name => 'api_office_only', acl_type => 'host', mappings => [$map],
);

my $user = App::Netdisco::DB->resultset('User')->new_result({
  username        => 'apiuser',
  token           => 'secret-api-token',
  token_from      => time,
  token_no_expire => 1,
  token_acl       => 'api_office_only',
});
$user->in_storage(1);

# stands in for the DBIC belongs_to relation that would normally be
# populated by the { prefetch => { token_acl_name => ... } } in
# validate_api_token; there is no live DB in xt/ to actually prefetch from
local *App::Netdisco::DB::Result::User::token_acl_name = sub { return $token_acl };

local *App::Netdisco::Web::Auth::Provider::DBIC::schema  = sub { return FakeSchema->new($user) };

my $provider = App::Netdisco::Web::Auth::Provider::DBIC->new({});

# TESTS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

{
  config->{'host_groups'} = {};
  local *App::Netdisco::Web::Auth::Provider::DBIC::request
    = sub { return FakeRequest->new('192.0.2.55') };

  my $authed = $provider->validate_api_token('secret-api-token');
  ok($authed, 'API token request from a client IP inside the token ACL is authenticated');
  is($authed && $authed->username, 'apiuser', 'the authenticated user is the token owner');
}

{
  config->{'host_groups'} = {};
  local *App::Netdisco::Web::Auth::Provider::DBIC::request
    = sub { return FakeRequest->new('203.0.113.9') };

  my $authed = $provider->validate_api_token('secret-api-token');
  ok(!$authed, 'API token request from a client IP outside the token ACL is denied');
}

{
  config->{'host_groups'} = {};
  local *App::Netdisco::Web::Auth::Provider::DBIC::request
    = sub { return FakeRequest->new('192.0.2.55') };

  my $authed = $provider->validate_api_token('not-the-right-token');
  ok(!$authed, 'an unrecognised token is denied regardless of client IP');
}

done_testing;
