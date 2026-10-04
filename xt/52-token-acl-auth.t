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
# The client IP is read by trusted_client_address(), so the fake request is
# installed in App::Netdisco::Util::Web and not in the provider.
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
# The peer and the REMOTE_ADDR a forwarded header overwrote are held apart,
# because the ACL decision must follow the peer. With one argument they match.
sub new {
  my ($class, $peer, %rewritten_by_the_proxy_header) = @_;
  return bless {
    peer      => $peer,
    remote    => ($rewritten_by_the_proxy_header{remote}    || $peer),
    forwarded => ($rewritten_by_the_proxy_header{forwarded} || undef),
    no_peer   => ($rewritten_by_the_proxy_header{no_peer}   || 0),
  }, $class;
}
sub remote_address        { return $_[0]->{remote} }
sub forwarded_for_address { return $_[0]->{forwarded} }
sub env {
  return { PATH_INFO => '/' } if $_[0]->{no_peer};
  return { REMOTE_ADDR => $_[0]->{remote},
           'netdisco.peer_address' => $_[0]->{peer},
           ($_[0]->{forwarded}
             ? (HTTP_X_FORWARDED_FOR => $_[0]->{forwarded}) : ()) };
}

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
  local *App::Netdisco::Util::Web::request
    = sub { return FakeRequest->new('192.0.2.55') };

  my $authed = $provider->validate_api_token('secret-api-token');
  ok($authed, 'API token request from a client IP inside the token ACL is authenticated');
  is($authed && $authed->username, 'apiuser', 'the authenticated user is the token owner');
}

{
  config->{'host_groups'} = {};
  local *App::Netdisco::Util::Web::request
    = sub { return FakeRequest->new('203.0.113.9') };

  my $authed = $provider->validate_api_token('secret-api-token');
  ok(!$authed, 'API token request from a client IP outside the token ACL is denied');
}

{
  config->{'host_groups'} = {};
  local *App::Netdisco::Util::Web::request
    = sub { return FakeRequest->new('192.0.2.55') };

  my $authed = $provider->validate_api_token('not-the-right-token');
  ok(!$authed, 'an unrecognised token is denied regardless of client IP');
}

{
  config->{'host_groups'} = {};
  setting('trusted_proxies' => []);
  local *App::Netdisco::Util::Web::request = sub {
    return FakeRequest->new('203.0.113.9',
      remote => '192.0.2.55', forwarded => '192.0.2.55');
  };

  my $authed = $provider->validate_api_token('secret-api-token');
  ok(!$authed,
    'tokenAcl__no_proxy_and_a_peer_outside_the_acl__is_denied_whatever_the_header_says');
}

{
  config->{'host_groups'} = {};
  setting('trusted_proxies' => []);
  local *App::Netdisco::Util::Web::request = sub {
    return FakeRequest->new('192.0.2.55',
      remote => '203.0.113.9', forwarded => '203.0.113.9');
  };

  my $authed = $provider->validate_api_token('secret-api-token');
  ok($authed,
    'tokenAcl__no_proxy_and_a_peer_inside_the_acl__is_allowed_whatever_the_header_says');
}

{
  config->{'host_groups'} = {};
  setting('trusted_proxies' => ['203.0.113.9']);
  local *App::Netdisco::Util::Web::request = sub {
    return FakeRequest->new('203.0.113.9',
      remote => '192.0.2.55', forwarded => '192.0.2.55');
  };

  my $authed = $provider->validate_api_token('secret-api-token');
  ok($authed,
    'tokenAcl__a_trusted_proxy__follows_the_address_that_proxy_appended');

  setting('trusted_proxies' => []);
}

{
  # A UNIX socket client has no peer address and is judged as loopback.
  config->{'host_groups'} = {};
  setting('trusted_proxies' => []);

  my $admits_loopback = FakeAccessControlListName->new(
    acl_name => 'api_office_only', acl_type => 'host',
    mappings => [ FakeAccessControlListMap->new( id => 2,
      left_acl  => FakeAccessControlList->new(id => 2, rules => ['127.0.0.0/8']),
      right_acl => undef ) ],
  );
  local *App::Netdisco::DB::Result::User::token_acl_name
    = sub { return $admits_loopback };
  local *App::Netdisco::Util::Web::request = sub {
    return FakeRequest->new(undef,
      remote => '192.0.2.55', forwarded => '192.0.2.55');
  };

  my $authed = $provider->validate_api_token('secret-api-token');
  ok($authed,
    'tokenAcl__unix_socket_peer__is_judged_as_loopback');
}

{
  # NetAddr::IP::Lite->new(undef) is a truthy 0.0.0.0/0 in every stable
  # release, which a negated list matches, so an absent address is refused.
  config->{'host_groups'} = {};
  setting('trusted_proxies' => []);

  my $admits_all_but_ten = FakeAccessControlListName->new(
    acl_name => 'api_office_only', acl_type => 'host',
    mappings => [ FakeAccessControlListMap->new( id => 3,
      left_acl  => FakeAccessControlList->new(id => 3, rules => ['!10.0.0.0/8']),
      right_acl => undef ) ],
  );
  local *App::Netdisco::DB::Result::User::token_acl_name
    = sub { return $admits_all_but_ten };
  local *App::Netdisco::Util::Web::request
    = sub { return FakeRequest->new(undef, no_peer => 1) };

  my $authed = $provider->validate_api_token('secret-api-token');
  ok(!$authed,
    'tokenAcl__no_peer_address_at_all__is_denied_by_a_list_that_would_admit_it');
}

done_testing;
