#!/usr/bin/env perl

# The VRF collection switch ships off. These helpers are the only gate later
# tasks use, so the fake SNMP object dies on any call made while the switch is
# off: a device whose class lacks VRF support must behave as it does today.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco::Configuration;
use Dancer qw/:script !pass/;
use App::Netdisco::Util::VRF qw/
  vrf_collection_enabled vrf_skipped netdisco_vrf vrf_instances_for
/;

{
  package FakeDevice;
  sub new { bless { ip => $_[1] }, $_[0] }
  sub ip  { $_[0]{ip} }
}

{
  package FakeSNMP;
  sub new { my ($class, %args) = @_; bless { %args, calls => [] }, $class }
  sub vrf_instances_complete { push @{$_[0]{calls}}, 'complete'; $_[0]{complete} }
  sub vrf_instances          { push @{$_[0]{calls}}, 'instances'; $_[0]{instances} }
}

{
  package DyingSNMP;
  our $AUTOLOAD;
  sub AUTOLOAD { die "SNMP method called while VRF collection is off: $AUTOLOAD" }
  sub DESTROY {}
}

sub with_settings {
  my ($code, %settings) = @_;
  my %saved = map { $_ => setting($_) } keys %settings;
  set($_ => $settings{$_}) for keys %settings;
  $code->();
  set($_ => $saved{$_}) for keys %saved;
}

my $device = FakeDevice->new('192.0.2.1');

subtest 'store_vrfs__default__off' => sub {
  ok(!setting('store_vrfs'), 'store_vrfs is off');
  is_deeply(setting('skip_vrf_devices'), [], 'skip_vrf_devices is empty');
  is_deeply(setting('vrf_no_name'), [], 'vrf_no_name is empty');
  is_deeply(setting('vrf_no_devicevrf'), [], 'vrf_no_devicevrf is empty');
  ok(!vrf_collection_enabled($device), 'collection disabled by default');
};

subtest 'vrf_collection_enabled__on__true' => sub {
  with_settings(sub {
    ok(vrf_collection_enabled($device), 'enabled');
  }, store_vrfs => 1);
};

subtest 'vrf_collection_enabled__on_but_device_in_skip_vrf_devices__false' => sub {
  with_settings(sub {
    ok(!vrf_collection_enabled($device), 'skipped device');
    ok(vrf_collection_enabled(FakeDevice->new('198.51.100.9')), 'other device');
  }, store_vrfs => 1, skip_vrf_devices => ['192.0.2.1']);
};

subtest 'vrf_skipped__global_name__true' => sub {
  with_settings(sub {
    ok(vrf_skipped($device, 'MGMT'), 'listed name');
    ok(!vrf_skipped($device, 'mgmt'), 'match is case sensitive');
    ok(!vrf_skipped($device, 'red'), 'unlisted name');
  }, vrf_no_name => ['MGMT']);
};

subtest 'vrf_skipped__device_and_name__true' => sub {
  with_settings(sub {
    ok(vrf_skipped($device, 'red'), 'listed device and name');
    ok(!vrf_skipped(FakeDevice->new('198.51.100.9'), 'red'), 'other device');
    ok(!vrf_skipped($device, 'blue'), 'other name');
  }, vrf_no_devicevrf => ['192.0.2.1:red']);
};

subtest 'vrf_skipped__default_table__never' => sub {
  with_settings(sub {
    ok(!vrf_skipped($device, 'default'), 'default by SNMP::Info name');
    ok(!vrf_skipped($device, ''), 'default by stored name');
  }, vrf_no_name => ['default', ''],
     vrf_no_devicevrf => ['192.0.2.1:default', '192.0.2.1:']);
};

subtest 'netdisco_vrf__default__empty_string' => sub {
  is(netdisco_vrf('default'), '', 'default maps to empty');
  is(netdisco_vrf('red'), 'red', 'named VRF unchanged');
  is(netdisco_vrf('Default'), 'Default', 'only exact default maps');
};

subtest 'vrf_instances_for__unsupported_class__undef' => sub {
  with_settings(sub {
    my $snmp = FakeSNMP->new(complete => undef, instances => {});
    is(vrf_instances_for($device, $snmp), undef, 'undef');
    is_deeply($snmp->{calls}, ['complete'], 'instances never read');
  }, store_vrfs => 1);
};

subtest 'vrf_instances_for__switch_off__undef_without_snmp_calls' => sub {
  my $result = eval { vrf_instances_for($device, bless {}, 'DyingSNMP') };
  is($@, '', 'no SNMP method called');
  is($result, undef, 'undef');
};

subtest 'vrf_instances_for__skipped_names__removed_default_kept' => sub {
  with_settings(sub {
    my $snmp = FakeSNMP->new(complete => 1,
      instances => { default => 'default', MGMT => 'MGMT', red => 'red' });
    is_deeply(vrf_instances_for($device, $snmp),
      { default => 'default', red => 'red' }, 'MGMT removed');
  }, store_vrfs => 1, vrf_no_name => ['MGMT', 'default']);
};

subtest 'vrf_instances_for__incomplete_walk__still_returns_names' => sub {
  with_settings(sub {
    my $snmp = FakeSNMP->new(complete => 0, instances => { red => 'red' });
    is_deeply(vrf_instances_for($device, $snmp), { red => 'red' }, 'names');
  }, store_vrfs => 1);
};

subtest 'build_pl__snmp_info_floor__3_985000' => sub {
  open my $fh, '<', 'Build.PL' or die "Build.PL: $!";
  my $text = do { local $/; <$fh> };
  like($text, qr/'SNMP::Info'\s*=>\s*'3\.985000'/, 'floor is 3.985000');
};

done_testing;
