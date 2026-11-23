#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catdir catfile updir/;
use FindBin;
use File::Temp ();

# metrics_{ports,macs,neighbors,vlans}_per_device: counts per device, one
# series each, so each is off by default. The counts are checked against rows
# made for a documentation address inside a transaction that is rolled back,
# with the request served on the same handle so it sees them; without a
# database only the on/off switch is checked.
#
# Review of #1839: a port with no status was in the total but in neither
# up nor down, and a device with nothing to count had no sample at all, so
# an alert on 0 never fired.

my $envdir;
BEGIN {
  # As xt/94: the app refuses to build without a public directory, and the
  # route registers at load time only if metrics_path comes from a file.
  $ENV{DANCER_PUBLIC} ||= catdir($FindBin::Bin, updir(), 'share', 'public');
  $envdir = File::Temp->newdir(CLEANUP => 1);
  open my $env, '>', catfile("$envdir", 'testing.yml')
    or die "cannot write the test environment file: $!";
  print $env "metrics_path: '/xt-metrics'\n";
  close $env;
  $ENV{DANCER_ENVDIR} = "$envdir";
  $ENV{DANCER_ENVIRONMENT} = 'testing';
}

use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;

my $psgi = catfile($FindBin::Bin, updir(), 'bin', 'netdisco-web-fg');
my $app  = eval { Plack::Util::load_psgi($psgi) };
BAIL_OUT("could not load $psgi: $@") unless $app;

# As xt/94, Dancer's keywords are not imported here.
sub setting { return Dancer::Config::setting(@_) }

my @switches = map { "metrics_${_}_per_device" } qw/ports macs neighbors vlans/;
my @metrics = qw/
  netdisco_device_ports_total netdisco_device_ports_oper_up
  netdisco_device_ports_oper_down netdisco_device_ports_admin_down
  netdisco_device_macs netdisco_device_neighbors netdisco_device_vlans
/;

my $schema = eval {
  my $s = Dancer::Plugin::DBIC::schema('netdisco');
  $s->storage->dbh_do(sub { $_[1]->do('SELECT 1 FROM admin LIMIT 0') });
  $s;
};
my $why = $@;

test_psgi $app, sub {
  my $cb = shift;
  setting('metrics_allow' => []);
  setting('metrics_token' => '');

  my $body = $cb->(GET '/xt-metrics')->content;
  unlike $body, qr/^# TYPE $_ /m, "metricsDeviceCounts__shipped_default__no_$_"
    for @metrics;

  setting($_ => 1) for @switches;
  $body = $cb->(GET '/xt-metrics')->content;
  like $body, qr/^# TYPE $_ gauge$/m, "metricsDeviceCounts__switched_on__emits_$_"
    for @metrics;

  SKIP: {
    skip "no usable netdisco database: $why", 10 if not $schema;

    # 192.0.2.0/24 is documentation space, so no real device is touched.
    my $dev = '192.0.2.1';
    eval {
      $schema->txn_do(sub {
        $schema->resultset('Device')->create({ ip => $dev });
        my $ports = $schema->resultset('DevicePort');
        $ports->create({ ip => $dev, port => 'Gi1', up => 'up', up_admin => 'up',
          remote_ip => '192.0.2.2' });
        $ports->create({ ip => $dev, port => 'Gi2', up => 'up', up_admin => 'up',
          remote_ip => '192.0.2.2' });
        $ports->create({ ip => $dev, port => 'Gi3', up => 'down', up_admin => 'up' });
        $ports->create({ ip => $dev, port => 'Gi4', up => 'lowerLayerDown', up_admin => 'down' });
        $ports->create({ ip => $dev, port => 'Gi5' });
        $schema->resultset('Device')->create({ ip => '192.0.2.3' });
        my $nodes = $schema->resultset('Node');
        $nodes->create({ mac => '02:00:00:00:00:01', switch => $dev, port => 'Gi3', vlan => '1', active => \'true' });
        $nodes->create({ mac => '02:00:00:00:00:02', switch => $dev, port => 'Gi3', vlan => '1', active => \'true' });
        $nodes->create({ mac => '02:00:00:00:00:03', switch => $dev, port => 'Gi3', vlan => '1', active => \'false' });
        $schema->resultset('DeviceVlan')->create({ ip => $dev, vlan => $_ }) for (1, 10);

        my $out = $cb->(GET '/xt-metrics')->content;
        my $got_for = sub { my $ip = shift;
          return { map { $_ => ($out =~ m/^$_\{device="$ip",tenant="netdisco"\} (\S+)$/m ? $1 : undef) }
            @metrics } };
        my %got = %{ $got_for->($dev) };

        is $got{netdisco_device_ports_total}, 5, 'metricsDeviceCounts__rows__every_port';
        is $got{netdisco_device_ports_oper_up}, 2, 'metricsDeviceCounts__rows__oper_up';
        is $got{netdisco_device_ports_oper_down}, 3,
          'metricsDeviceCounts__rows__oper_down_is_anything_not_up_even_no_status';
        is $got{netdisco_device_ports_admin_down}, 2,
          'metricsDeviceCounts__rows__admin_down_includes_no_status';
        is $got{netdisco_device_macs}, 2, 'metricsDeviceCounts__rows__archived_macs_left_out';
        is $got{netdisco_device_neighbors}, 1,
          'metricsDeviceCounts__rows__a_neighbor_on_two_ports_counts_once';
        is $got{netdisco_device_vlans}, 2, 'metricsDeviceCounts__rows__vlans';
        is_deeply $got_for->('192.0.2.3'), { map { ($_ => 0) } @metrics },
          'metricsDeviceCounts__nothing_to_count__reads_0';
        is $got{netdisco_device_ports_oper_up} + $got{netdisco_device_ports_oper_down},
          $got{netdisco_device_ports_total}, 'metricsDeviceCounts__rows__up_and_down_add_up';

        # the same per-device ACL as the job series (xt/231)
        setting('metrics_per_device_only' => ['198.51.100.0/24']);
        unlike $cb->(GET '/xt-metrics')->content, qr/device="$dev"/,
          'metricsDeviceCounts__per_device_only_not_matching__left_out';
        setting('metrics_per_device_only' => []);
        die "rollback\n";
      });
    };
    die $@ if $@ and $@ !~ /rollback/;
  }

  setting($_ => 0) for @switches;
};

done_testing;
