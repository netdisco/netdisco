#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'once'; # the glob overrides below are single-use by design

# Deleting a manual topology link resets is_uplink, manual_topo and the
# remote_* columns on both of its ports. The route did that whether or not a
# manual link matched, so naming the two ends of a discovered uplink cleared
# its is_uplink flag, and with that the portctl_uplinks guard stopped
# protecting it until the next discovery. Only a deleted link may reset its
# ports.
#
# Only the DB edges are faked: the user, its roles, the schema and the
# devices. The route and its checks are the real ones, and the user is an
# admin so the role scoping of #1691 passes without a database.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Web;
use Dancer ':tests';
use Dancer::Test;

config->{logger} = 'null';

my $deleted;    # what the delete of the manual link returns
my @updated;    # updates made to device ports

package FakeSchema;
sub new       { return bless {}, $_[0] }
sub txn_do    { return $_[1]->() }
sub resultset { return $_[0] }
sub search    { return $_[0] }
sub delete    { return $deleted }

package FakePorts;
sub new    { return bless { ip => $_[1] }, $_[0] }
sub search { my ($s, $q) = @_; return bless { %$s, port => $q->{port} }, ref $s }
sub single { return $_[0] }
sub update { my ($s, $v) = @_; push @updated, [ $s->{ip}, $s->{port}, $v ]; return $s }

package FakeDevice;
sub new        { return bless { ip => $_[1] }, $_[0] }
sub in_storage { 1 }
sub ports      { return FakePorts->new($_[0]->{ip}) }

package main;

no warnings 'redefine';
*Dancer::Plugin::Auth::Extensible::logged_in_user = sub { return { username => 'someone' } };
*Dancer::Plugin::Auth::Extensible::user_roles     = sub { return wantarray ? ('admin') : ['admin'] };
*App::Netdisco::Web::Plugin::AdminTask::Topology::schema     = sub { return FakeSchema->new };
*App::Netdisco::Web::Plugin::AdminTask::Topology::get_device = sub { return FakeDevice->new($_[0]) };

set trust_x_remote_user => 1;

sub delete_link {
  @updated = ();
  Dancer::Cookies->init;
  # Dancer::Test drops a dashed name from its headers argument before the
  # request is built (see xt/57), so the XHR marker goes in the environment
  local $ENV{HTTP_X_REQUESTED_WITH} = 'XMLHttpRequest';
  return dancer_response(POST => '/ajax/control/admin/topology/del', {
    headers => [ 'X-REMOTE_USER' => 'someone' ],
    params  => { dev1 => '192.0.2.1', port1 => 'Gi1/1',
                 dev2 => '192.0.2.2', port2 => 'Gi1/2' },
  });
}

# DBI reports "no rows" as the true string "0E0" (see xt/98)
foreach my $none ('0E0', 0) {
  $deleted = $none;
  my $res = delete_link();
  is $res->status, 200, "topology_del__no_manual_link_matched_($none)__still_answers";
  is scalar @updated, 0, "topology_del__no_manual_link_matched_($none)__leaves_both_ports_alone";
}

$deleted = 1;
my $res = delete_link();
is $res->status, 200, 'topology_del__a_manual_link_matched__answers';
is_deeply [ map { [ $_->[0], $_->[1], $_->[2]->{is_uplink} ] } @updated ],
          [ [ '192.0.2.1', 'Gi1/1', \'false' ], [ '192.0.2.2', 'Gi1/2', \'false' ] ],
  'topology_del__a_manual_link_matched__resets_both_of_its_ports';

done_testing;
