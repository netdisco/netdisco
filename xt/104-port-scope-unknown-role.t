#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing'; delete $ENV{ND2_DO_FORCE} }

use Test::More 0.88;
use App::Netdisco;
use Dancer qw/setting/;
use App::Netdisco::Util::Port 'port_acl_by_role_check';

{ package Test::FakeUser;
  sub new { my ($c, %a) = @_; return bless { port_control => 1, admin => 0, portctl_role => '', %a }, $c }
  sub port_control { $_[0]->{port_control} }
  sub admin        { $_[0]->{admin} }
  sub portctl_role { $_[0]->{portctl_role} }
}

my $IN  = { ip => '192.168.0.11' };
my $OUT = { ip => '192.168.0.22' };
my $PORT = { ip => '192.168.0.11', port => 'Gi1/1' };

setting('host_groups' => { leafgroup => [$IN->{ip}] });
setting('portctl_by_role' => {
  leafonly  => { 'group:leafgroup' => [] },
  plainonly => [$IN->{ip}],
});

subtest 'portAclByRoleCheck__a_role_with_no_ACL__is_refused' => sub {
  ok !port_acl_by_role_check($PORT, $IN, Test::FakeUser->new(portctl_role => 'nosuchrole')),
    'covered device refused';
  ok !port_acl_by_role_check($PORT, $OUT, Test::FakeUser->new(portctl_role => 'nosuchrole')),
    'uncovered device refused';
};

subtest 'portAclByRoleCheck__a_user_with_no_role__keeps_every_port' => sub {
  ok port_acl_by_role_check($PORT, $OUT, Test::FakeUser->new),
    'an unscoped port_control user is unaffected';
  ok !port_acl_by_role_check($PORT, $OUT, Test::FakeUser->new(port_control => 0)),
    'a user without port_control is refused';
};

subtest 'portAclByRoleCheck__an_admin__keeps_every_port' => sub {
  ok port_acl_by_role_check($PORT, $OUT,
       Test::FakeUser->new(admin => 1, portctl_role => 'nosuchrole')),
    'an admin is not scoped by a role';
};

subtest 'portAclByRoleCheck__a_known_role__is_matched_as_before' => sub {
  my $hash = Test::FakeUser->new(portctl_role => 'leafonly');
  ok  port_acl_by_role_check($PORT, $IN,  $hash), 'device and port role allows its device';
  ok !port_acl_by_role_check($PORT, $OUT, $hash), 'device and port role refuses another';

  my $list = Test::FakeUser->new(portctl_role => 'plainonly');
  ok  port_acl_by_role_check($PORT, $IN,  $list), 'device list role allows its device';
  ok !port_acl_by_role_check($PORT, $OUT, $list), 'device list role refuses another';
};

done_testing;
