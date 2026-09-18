#!/usr/bin/env perl

# portctl_by_role scopes a port_control user to named devices, and optionally
# to ports within them. The device details view consults it before offering an
# editable location or contact cell, but the write paths behind those cells did
# not, so a scoped user could change either on any device.
#
# Location, contact and the custom fields share one route and reach the queue
# without a worker check phase, which is why the route is where this is
# enforced rather than the worker.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVIRONMENT} = 'testing' }

use Test::More 0.88;
use File::Slurper 'read_text';
use App::Netdisco;
use Dancer qw/setting/;
use App::Netdisco::Util::Port 'device_acl_by_role_check';

{ package Test::FakeUser;
  sub new { my ($c, %a) = @_; return bless { port_control => 1, admin => 0, portctl_role => undef, %a }, $c }
  sub port_control { $_[0]->{port_control} }
  sub admin        { $_[0]->{admin} }
  sub portctl_role { $_[0]->{portctl_role} }
}

my $IN  = '192.168.0.11';
my $OUT = '192.168.0.22';

# the shape sync_portctl_roles builds from a host_port ACL made in the admin UI
setting('host_groups' => { leafgroup => [$IN] });
setting('portctl_by_role' => {
  leafonly  => { 'group:leafgroup' => [] },   # empty rhs means any port
  plainonly => [$IN],                          # the yaml list form
});

subtest 'deviceAclByRoleCheck__a_role_ACL_of_devices_and_ports__is_matched_on_the_device' => sub {
  my $user = Test::FakeUser->new(portctl_role => 'leafonly');
  ok  device_acl_by_role_check($IN,  $user), 'a device the role covers is allowed';
  ok !device_acl_by_role_check($OUT, $user), 'a device it does not cover is refused';
};

subtest 'deviceAclByRoleCheck__a_role_ACL_naming_devices_only__is_matched_the_same_way' => sub {
  my $user = Test::FakeUser->new(portctl_role => 'plainonly');
  ok  device_acl_by_role_check($IN,  $user), 'covered device allowed';
  ok !device_acl_by_role_check($OUT, $user), 'uncovered device refused';
};

subtest 'deviceAclByRoleCheck__a_user_with_no_role__keeps_every_device' => sub {
  my $user = Test::FakeUser->new();
  ok device_acl_by_role_check($OUT, $user), 'an unscoped port_control user is unaffected';
};

subtest 'deviceAclByRoleCheck__an_admin__keeps_every_device' => sub {
  my $user = Test::FakeUser->new(admin => 1, portctl_role => 'leafonly');
  ok device_acl_by_role_check($OUT, $user), 'an admin is not scoped by a role';
};

subtest 'deviceAclByRoleCheck__without_port_control_or_a_known_role__refuses' => sub {
  ok !device_acl_by_role_check($IN, Test::FakeUser->new(port_control => 0)),
    'a user without port_control is refused';
  ok !device_acl_by_role_check($IN, Test::FakeUser->new(portctl_role => 'nosuchrole')),
    'a role with no ACL is refused rather than allowed';
  ok !device_acl_by_role_check(undef, Test::FakeUser->new), 'no device is refused';
  ok !device_acl_by_role_check($IN, undef), 'no user is refused';
};

subtest 'writePaths__both_scoped_routes__consult_the_check_and_sync_first' => sub {
  # an import satisfies a search for the sub name alone, so look for the calls
  my $pc = read_text('lib/App/Netdisco/Web/PortControl.pm');
  like $pc, qr/device_acl_by_role_check\( param\('device'\), logged_in_user \)/,
    'the portcontrol route puts the submitted device to the check';
  cmp_ok index($pc, 'sync_portctl_roles();'), '<',
         index($pc, 'device_acl_by_role_check( param'),
    'and syncs the database roles first';

  my $tp = read_text('lib/App/Netdisco/Web/Plugin/AdminTask/Topology.pm');
  like $tp, qr/port_acl_by_role_check\(\$port, \$device, logged_in_user\)/,
    'the topology routes put each port to the by-role check';
  is scalar(() = $tp =~ m/_scope_ok\(param\('dev1'\), param\('port1'\)\)/g), 2,
    'both topology routes are guarded, not just one';
};

done_testing;
