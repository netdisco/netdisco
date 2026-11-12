#!/usr/bin/env perl

# Every web request applies the current tenant's ACL Manager config through an
# early `before` hook. Things easy to break without noticing:
# - /t/<tenant>/ forwards, so the hooks run twice; a worker that served a
#   tenant must not leave that tenant's roles for the next default request;
# - the hook must sit ahead of Web::AuthN's hooks, whose token ACL checks
#   resolve group:<name> through host_groups;
# - the role dropdown and the ACL delete tell YAML roles from database roles
#   through yaml_setting (they used to read the portctl_by_role_shadow key).
# The test route is under /ajax/ because Web.pm's catch-all, `any qr{^(?!/ajax/).*}`,
# is registered first.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing'; }

use lib 'xt/lib';
use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

# Dancer wraps each hook in a closure inside Dancer::Hook, so the registered
# code refs all belong to that package. To learn which module registered each
# `before` hook, in order, note the caller of `hook` as the hook is created.
my @BEFORE_HOOK_PACKAGES;
BEGIN {
  require Dancer::Hook;
  no warnings 'redefine';
  my $orig = \&Dancer::Hook::new;
  *Dancer::Hook::new = sub {
    push @BEFORE_HOOK_PACKAGES, scalar caller(1) if ($_[1] || '') eq 'before';
    goto &$orig;
  };
}

use App::Netdisco;
use App::Netdisco::Web;
use Dancer qw/:syntax :tests/;
use Dancer::Test;
use Dancer::Plugin::Ajax;
use Test::Netdisco::ManagedACL qw(stub_managed_config);
use App::Netdisco::Util::ManagedConfig qw(capture_yaml_settings);

# after the use lines, as Dancer switches warnings back on when imported
no warnings qw/once redefine/; # the glob overrides below are deliberate

my $IN  = '192.0.2.1';
my $OUT = '192.0.2.99';

setting('no_auth'     => 1);
# only requests that send X-REMOTE_USER (the admin route subtests) use it
set trust_x_remote_user => 1;
setting('tenant_tags' => ['east']);
config->{'portctl_by_role'} = {};
capture_yaml_settings();

ajax '/ajax/test/managed-config' => sub {
  content_type 'application/json';
  to_json { roles => setting('portctl_by_role') };
};

sub get_roles {
  my $path = shift;
  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  my $res = dancer_response(GET => $path);
  is $res->status, 200, "GET $path";
  return from_json($res->content)->{roles};
}

subtest 'web__a_change_between_requests__is_seen_by_the_next' => sub {
  stub_managed_config(version => 1, rows => { netdisco => {
    r => { type => 'host_port', maps => [ [[$IN]] ] } } });
  my $first = get_roles('/ajax/test/managed-config');
  my ($g1) = keys %{ $first->{r} || {} };
  like $g1, qr/^group:synthesized_group_netdisco_/, 'role loaded';

  stub_managed_config(version => 2, keep_cache => 1, rows => { netdisco => {
    r => { type => 'host_port', maps => [ [[$OUT]] ] } } });
  my $second = get_roles('/ajax/test/managed-config');
  my ($g2) = keys %{ $second->{r} || {} };
  (my $name = $g2 || '') =~ s/^group://;
  is_deeply setting('host_groups')->{$name}, [$OUT], 'new rules are in force';
};

subtest 'web__an_unchanged_counter__reads_no_rows' => sub {
  my $calls = stub_managed_config(version => 1, rows => { netdisco => {
    r => { type => 'host_port', maps => [ [[$IN]] ] } } });
  get_roles('/ajax/test/managed-config') for 1 .. 2;
  is $calls->{row_reads}, 1, 'rows read once for two requests';
};

my $TENANT_ROWS = {
  netdisco => { r => { type => 'host_port', maps => [ [[$IN]] ] } },
  east     => { r => { type => 'host_port', maps => [ [[$OUT]] ] } },
};

subtest 'web__a_tenant_url__applies_that_tenants_roles' => sub {
  stub_managed_config(version => 1, rows => $TENANT_ROWS);
  my $roles = get_roles('/t/east/ajax/test/managed-config');
  is_deeply [keys %{ $roles->{r} || {} }], ['group:synthesized_group_east_1'], 'east role';
};

subtest 'web__a_default_request_after_a_tenant_request__sees_the_default_roles' => sub {
  stub_managed_config(version => 1, rows => $TENANT_ROWS);
  get_roles('/t/east/ajax/test/managed-config');
  my $roles = get_roles('/ajax/test/managed-config');
  is_deeply [keys %{ $roles->{r} || {} }], ['group:synthesized_group_netdisco_1'], 'default role';
  is_deeply [grep { /synthesized_group_east_/ } map { keys %{ $_ || {} } } values %$roles], [],
    'nothing of east';
};

subtest 'web__each_pass_loads_at_most_once' => sub {
  my $calls = stub_managed_config(version => 1, rows => $TENANT_ROWS);
  get_roles('/ajax/test/managed-config');
  is $calls->{version_reads}, 1, 'plain request: one read';
  get_roles('/t/east/ajax/test/managed-config');
  is $calls->{version_reads}, 3, 'tenant request: two more (default, then east)';
};

subtest 'web__the_hook_is_registered_before_authn' => sub {
  my @pkgs = @BEFORE_HOOK_PACKAGES;
  my ($mc) = grep { $pkgs[$_] eq 'App::Netdisco::Web::ManagedConfig' } 0 .. $#pkgs;
  my ($au) = grep { $pkgs[$_] eq 'App::Netdisco::Web::AuthN' } 0 .. $#pkgs;
  ok defined $mc, 'managed config hook registered';
  ok defined $au, 'authn hook registered';
  ok +(defined $mc and defined $au and $mc < $au), 'managed config first';
};

subtest 'web__named_host_acls__appear_in_the_group_typeahead' => sub {
  stub_managed_config(version => 1, rows => { netdisco => {
    office => { type => 'host', maps => [ [[$IN]] ] },
    r      => { type => 'host_port', maps => [ [[$IN]] ] } } });
  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  my $res = dancer_response(GET => '/ajax/data/devices/typeahead?left_rule=group:');
  is $res->status, 200, 'typeahead answers';
  my $list = from_json($res->content);
  ok scalar(grep { $_ eq 'group:office' } @$list), 'group:office offered';
  is scalar(grep { /synthesized_group_/ } @$list), 0, 'no synthesized groups offered';
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

# the admin routes only need roles, so fake the user and its roles as xt/102
# does, and give the YAML a role y that the database doesn't have
sub as_admin {
  my $code = shift;
  local *Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'someone' } };
  local *Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? ('admin') : ['admin'] };
  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  config->{'portctl_by_role'} = { y => { 'group:somewhere' => ['192.0.2.50'] } };
  capture_yaml_settings();
  $code->();
}

subtest 'users__role_dropdown__lists_yaml_and_database_roles_once' => sub { as_admin(sub {
  stub_managed_config(version => 1, rows => { netdisco => {
    d => { type => 'host_port', maps => [ [[$IN]] ] } } });
  local *App::Netdisco::Web::Plugin::AdminTask::Users::schema = sub { FakeRS->new };

  my $res = dancer_response(GET => '/ajax/content/admin/users',
    { headers => [ 'X-REMOTE_USER' => 'someone' ] });
  is $res->status, 200, 'users list answers';
  # the page repeats the dropdown for each user row, so read the add form's
  my ($add) = $res->content =~ m{(data-form="add" name="port_control".*?</select>)}s;
  my @opts = ($add || '') =~ m{<option value="([^"]+)">Role: }g;
  is_deeply [sort @opts], [qw/d y/], 'each role is offered once';
}) };

subtest 'aclManagerDelete__a_role_also_in_yaml__keeps_users_on_it' => sub { as_admin(sub {
  local *App::Netdisco::Web::Plugin::AdminTask::ACLManager::schema = sub { FakeRS->new };
  local *App::Netdisco::Web::Plugin::AdminTask::ACLManager::acl_txn_do = sub { $_[0]->() };
  @FakeRS::UPDATES = ();

  my $res = dancer_response(POST => '/ajax/control/admin/aclmanager/delete',
    { headers => [ 'X-REMOTE_USER' => 'someone' ], params => { acl_name => 'y' } });
  is $res->status, 200, 'delete answers';
  my ($role) = grep { exists $_->{cond}->{portctl_role} } @FakeRS::UPDATES;
  ok $role, 'users on the role were updated';
  ok !exists $role->{set}->{portctl_role}, 'portctl_role is not cleared';
  ok !exists $role->{set}->{port_control}, 'port_control is not cleared';
}) };

done_testing;
