#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once';

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Backend::Job;
use App::Netdisco::Transport::SNMP;
use App::Netdisco::Worker::Plugin::Macsuck::InterfacesStatus ();

use Dancer qw/:moose :script !pass/;

# #1812: macsuck marked every port with a forwarding table entry up/up,
# overwriting the status the switch had just reported. The rule is only for
# data that carries no port status, such as offline submissions.

set logger => 'null';
config->{'device_auth'} = [{driver => 'snmp'}];

package FakePort;
sub new {
  my ($class, %col) = @_;
  return bless { %col, dirty => 0 }, $class;
}
sub set_column {
  my ($self, $col, $val) = @_;
  no warnings 'uninitialized';
  return if $self->{$col} eq $val and defined $self->{$col} == defined $val;
  $self->{$col} = $val;
  $self->{dirty} = 1;
}
sub is_changed { $_[0]{dirty} }
sub update     { $_[0]{dirty} = 0; $_[0] }
sub is_master  { $_[0]{is_master} }
sub up         { $_[0]{up} }
sub up_admin   { $_[0]{up_admin} }

package FakeSNMP;
our ($interfaces, $i_up, $i_up_admin);
sub new        { bless {}, $_[0] }
sub interfaces { $interfaces }
sub i_up       { $i_up }
sub i_up_admin { $i_up_admin }

package main;

our $snmp_fails = 0;
{
  no warnings 'redefine';
  *App::Netdisco::Transport::SNMP::reader_for
    = sub { return $snmp_fails ? undef : FakeSNMP->new };
}

# register_worker stores the wrapped subs by action, phase, namespace and priority
sub worker {
  my ($phase, $priority) = @_;
  return (grep { ref } @{ vars->{'workers'}{'macsuck'}{$phase}{'interfacesstatus'}{$priority} || [] })[0];
}

$FakeSNMP::interfaces = { 1 => 'Gi0/1', 2 => 'Gi0/2', 10 => 'Po1' };

sub run_job {
  my (%args) = @_;
  $FakeSNMP::i_up       = $args{i_up}       || {};
  $FakeSNMP::i_up_admin = $args{i_up_admin} || {};
  local $snmp_fails = $args{snmp_fails} || 0;

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });
  $device->in_storage(1);
  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'macsuck',
    is_offline => ($args{offline} ? 1 : 0),
  });

  vars->{'device_ports'} = $args{ports};
  vars->{'fwtable'} = { 0 => { map { ($_ => { '00:11:22:33:44:55' => 1 }) } @{ $args{fdb} } } };

  my $early = worker('early', 0);
  $early->($job) if $early and not $args{skip_early};
  worker('main', 100)->($job);
  worker('store', 0)->($job);
  return $args{ports};
}

sub port { FakePort->new(port => $_[0], up => $_[1], up_admin => $_[2], is_master => $_[3]) }

subtest 'early__registered__resets_reported_ports' => sub {
  ok worker('early', 0), 'an early worker is registered';
};

subtest 'store__port_status_from_snmp__keeps_switch_status' => sub {
  my $p = run_job(
    ports => { 'Gi0/1' => port('Gi0/1', 'up', 'up') },
    i_up => { 1 => 'down' }, i_up_admin => { 1 => 'up' },
    fdb => ['Gi0/1'],
  );
  is $p->{'Gi0/1'}->up, 'down', 'oper status from the switch';
  is $p->{'Gi0/1'}->up_admin, 'up', 'admin status from the switch';
};

subtest 'store__offline_job__marks_port_up_from_fdb' => sub {
  my $p = run_job(
    offline => 1,
    ports => { 'Gi0/1' => port('Gi0/1', 'down', 'down') },
    i_up => { 1 => 'down' }, i_up_admin => { 1 => 'down' },
    fdb => ['Gi0/1'],
  );
  is $p->{'Gi0/1'}->up, 'up', 'the snmp worker does not run offline';
  is $p->{'Gi0/1'}->up_admin, 'up';
};

subtest 'store__snmp_gave_no_status_for_port__marks_port_up_from_fdb' => sub {
  my $p = run_job(
    ports => { 'Gi0/2' => port('Gi0/2', 'down', 'down') },
    i_up => { 1 => 'down' },
    fdb => ['Gi0/2'],
  );
  is $p->{'Gi0/2'}->up, 'up';
};

subtest 'store__port_missing_from_interfaces__marks_port_up_from_fdb' => sub {
  my $p = run_job(
    ports => { 'Gi0/9' => port('Gi0/9', 'down', 'down') },
    i_up => { 1 => 'down' },
    fdb => ['Gi0/9'],
  );
  is $p->{'Gi0/9'}->up, 'up';
};

subtest 'store__snmp_connect_fails__marks_port_up_from_fdb' => sub {
  my $p = run_job(
    snmp_fails => 1,
    ports => { 'Gi0/1' => port('Gi0/1', 'down', 'down') },
    fdb => ['Gi0/1'],
  );
  is $p->{'Gi0/1'}->up, 'up';
};

subtest 'early__previous_online_job__offline_job_still_marked_up' => sub {
  run_job(
    ports => { 'Gi0/1' => port('Gi0/1', 'down', 'up') },
    i_up => { 1 => 'down' }, i_up_admin => { 1 => 'up' },
    fdb => ['Gi0/1'],
  );
  my $p = run_job(
    offline => 1,
    ports => { 'Gi0/1' => port('Gi0/1', 'down', 'down') },
    fdb => ['Gi0/1'],
  );
  is $p->{'Gi0/1'}->up, 'up', 'marks from the earlier job do not carry over';
};

subtest 'store__lag_master_without_reported_status__not_marked_up' => sub {
  my $p = run_job(
    ports => { 'Po9' => port('Po9', 'down', 'down', 1) },
    fdb => ['Po9'],
  );
  is $p->{'Po9'}->up, 'down';
  is $p->{'Po9'}->up_admin, 'down';
};

subtest 'main__i_up_admin_undef__port_still_marked' => sub {
  my $p = run_job(
    ports => { 'Gi0/1' => port('Gi0/1', 'up', 'up') },
    i_up => { 1 => 'down' },
    fdb => ['Gi0/1'],
  );
  is $p->{'Gi0/1'}->up, 'down';
};

done_testing;
