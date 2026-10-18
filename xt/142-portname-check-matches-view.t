#!/usr/bin/env perl

# The device ports view offers a port name for editing when port_acl_name
# allows it, which is the by-role check alone. From bf66e0b5 the portname
# worker checked port_acl_service instead, which also refuses under
# portctl_nameonly and on uplink, phone and WAP ports, so the backend failed
# a name change the view had just offered - and with portctl_nameonly, the
# setting for allowing only name changes, it failed every one of them.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; delete $ENV{ND2_DO_FORCE} }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use lib 'xt/lib';
use Test::Netdisco::ManagedACL 'stub_managed_acls';
use App::Netdisco::Backend::Job;
use App::Netdisco::Util::Port ();

use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';

{ package Test::FakeUser;
  sub new { my ($c, %a) = @_; return bless { port_control => 1, admin => 0, portctl_role => '', %a }, $c }
  sub port_control { $_[0]->{port_control} }
  sub admin        { $_[0]->{admin} }
  sub portctl_role { $_[0]->{portctl_role} }
}

{ package Test::FakeDevice;
  sub new { my ($c, %a) = @_; return bless { %a }, $c }
  sub ip         { $_[0]->{ip} }
  sub in_storage { 1 }
}

{ package Test::FakePort;
  sub new { my ($c, %a) = @_; return bless { ip => '192.168.0.11', port => 'Gi1/1', %a }, $c }
  sub AUTOLOAD { our $AUTOLOAD; (my $m = $AUTOLOAD) =~ s/.*:://; $_[0]->{$m} }
  sub DESTROY {}
  sub can { my ($s, $m) = @_; return ($m =~ m/^remote_is_/ ? 1 : $s->SUPER::can($m)) }
}

my $PORT;

# PortName imports this when it compiles, so it must be replaced before it is
# loaded. it can't reach a database here.
BEGIN {
  no warnings 'redefine';
  *App::Netdisco::Util::Port::get_port = sub { $PORT };
}

use App::Netdisco::Worker::Plugin::PortName;

my ($check) = @{ vars->{'workers'}->{'portname'}->{'check'}->{'_base_'}->{0} };
ok $check, 'the portname check worker is registered';

my $IN  = Test::FakeDevice->new(ip => '192.168.0.11');
my $OUT = Test::FakeDevice->new(ip => '192.168.0.22');

setting('portctl_by_role' => { plainonly => [$IN->ip] });
stub_managed_acls({});

sub check_status {
  my ($device, $user) = @_;
  my $job = App::Netdisco::Backend::Job->new({
    job => 0, action => 'portname', device => $device,
    port => $PORT->port, subaction => 'new name', username => $user,
  });
  $job->add_status( $check->($job) );
  return $job->_statuslist->[-1]->status;
}

subtest 'portnameCheck__under_portctl_nameonly__allows_the_name' => sub {
  setting('portctl_nameonly' => 1);
  $PORT = Test::FakePort->new;
  is check_status($IN, Test::FakeUser->new), 'done',
    'a port_control user may still rename the port';
  setting('portctl_nameonly' => 0);
};

subtest 'portnameCheck__on_an_uplink__allows_the_name' => sub {
  setting('portctl_uplinks' => 0);
  $PORT = Test::FakePort->new(is_uplink => 1);
  is check_status($IN, Test::FakeUser->new), 'done',
    'portctl_uplinks guards port status, not the port name';
};

subtest 'portnameCheck__on_a_portctl_no_device__allows_the_name' => sub {
  # the Configuration wiki: "with the exception of changing the port name
  # which is always allowed", for both portctl_no and portctl_only
  setting('portctl_no' => [$IN->ip]);
  $PORT = Test::FakePort->new;
  is check_status($IN, Test::FakeUser->new), 'done', 'portctl_no leaves the name alone';
  setting('portctl_no' => []);

  setting('portctl_only' => [$OUT->ip]);
  is check_status($IN, Test::FakeUser->new), 'done', 'portctl_only leaves the name alone';
  setting('portctl_only' => []);
};

subtest 'portnameCheck__outside_the_users_role__still_refuses' => sub {
  $PORT = Test::FakePort->new(ip => $OUT->ip);
  is check_status($OUT, Test::FakeUser->new(portctl_role => 'plainonly')), 'error',
    'a role scoped to another device is refused';
  is check_status($OUT, Test::FakeUser->new(port_control => 0)), 'error',
    'a user without port_control is refused';
};

done_testing;
