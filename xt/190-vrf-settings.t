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
use App::Netdisco::DB;
use Dancer qw/:script !pass/;
use App::Netdisco::Util::VRF qw/
  vrf_collection_enabled vrf_skip_test netdisco_vrf vrf_instances_for
/;

{
  package FakeDevice;
  sub new { bless { ip => $_[1], is_pseudo => $_[2] }, $_[0] }
  sub ip  { $_[0]{ip} }
  sub is_pseudo { $_[0]{is_pseudo} }
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
  ok(!defined setting('vrf_no_name'), 'vrf_no_name is gone');
  is_deeply(setting('vrf_no_devicevrfs'), [], 'vrf_no_devicevrfs is empty');
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

# update() clears SNMP::Info's cache, which for a device read from a snapshot
# is the snapshot itself, and the context probe is a live get
subtest 'vrf_collection__offline_snapshot_device__behaves_as_switch_off' => sub {
  with_settings(sub {
    my $pseudo = FakeDevice->new('192.0.2.1', 1);
    ok(!vrf_collection_enabled($pseudo), 'collection disabled for a pseudo device');
    my $result = eval { vrf_instances_for($pseudo, bless {}, 'DyingSNMP') };
    is($@, '', 'no SNMP method called');
    is($result, undef, 'undef, as with the switch off');

    # Transport::SNMP marks an unstored device read from a snapshot file so
    my $from_file = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.2' });
    ok(vrf_collection_enabled($from_file), 'enabled before the snapshot is loaded');
    $from_file->set_column(is_pseudo => \'true');
    ok(!vrf_collection_enabled($from_file), 'disabled once marked pseudo');
  }, store_vrfs => 1);
};

sub skipped_names {
  my ($dev, @names) = @_;
  my $skipped = vrf_skip_test($dev);
  return [ grep { $skipped->($_) } @names ];
}

sub warnings_from {
  my $code = shift;
  my @warnings;
  no warnings 'redefine';
  local *App::Netdisco::Util::VRF::warning = sub { push @warnings, join '', @_ };
  $code->();
  return @warnings;
}

my @names = ('red', 'blue', 'MGMT', 'mgmt', 'lab-1', 'prelab-1', 'cust:a');

subtest 'vrf_skip_test__every_device__name_skipped' => sub {
  with_settings(sub {
    is_deeply(skipped_names($device, @names), ['MGMT'], 'exact and case sensitive');
  }, vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:MGMT' });
};

subtest 'vrf_skip_test__regex_and_case_flag__anchored_match' => sub {
  with_settings(sub {
    is_deeply(skipped_names($device, @names), ['MGMT', 'mgmt', 'lab-1'],
      'lab-.* does not match prelab-1');
  }, vrf_no_devicevrfs => { 'group:__ANY__' => ['vrf:(?i)mgmt', 'vrf:lab-.*'] });
};

subtest 'vrf_skip_test__device_key__other_device_untouched' => sub {
  with_settings(sub {
    is_deeply(skipped_names($device, @names), ['red'], 'listed device');
    is_deeply(skipped_names(FakeDevice->new('198.51.100.9'), @names), [], 'other device');
  }, vrf_no_devicevrfs => { '192.0.2.1' => 'vrf:red' });
};

subtest 'vrf_skip_test__colon_in_name__matched_whole' => sub {
  with_settings(sub {
    is_deeply(skipped_names($device, @names), ['cust:a'], 'cust:a');
  }, vrf_no_devicevrfs => { '192.0.2.1' => 'vrf:cust:a' });
};

subtest 'vrf_skip_test__ipv6_device_key__matched_as_address' => sub {
  my $v6 = FakeDevice->new('2001:db8::1');
  with_settings(sub {
    is_deeply(skipped_names($v6, @names), ['red'], 'key written long form');
    is_deeply(skipped_names(FakeDevice->new('2001:db8::'), 'red', '1:red'), [],
      'no collision with a VRF name starting with hex digits');
  }, vrf_no_devicevrfs => { '2001:0db8:0:0::1' => 'vrf:red' });
};

subtest 'vrf_skip_test__negation_and_op_and__every_vrf_but_listed' => sub {
  with_settings(sub {
    is_deeply(skipped_names($device, 'CORE', 'INTERNET', 'red'), ['red'], 'negated rule');
  }, vrf_no_devicevrfs => { '192.0.2.0/24' => '!vrf:(CORE|INTERNET)' });
  with_settings(sub {
    is_deeply(skipped_names($device, 'cust-1', 'cust-test', 'red'), ['cust-1'], 'op:and');
  }, vrf_no_devicevrfs => { '192.0.2.1' => ['op:and', 'vrf:cust-.*', '!vrf:.*-test'] });
};

subtest 'vrf_skip_test__property_and_group_keys__matched' => sub {
  my $cisco = FakeDevice->new('192.0.2.7');
  $cisco->{vendor} = 'cisco';
  no warnings 'once';
  local *FakeDevice::vendor = sub { $_[0]{vendor} };
  with_settings(sub {
    is_deeply(skipped_names($cisco, @names), ['blue'], 'vendor key');
    is_deeply(skipped_names($device, @names), ['red'], 'group key');
  }, host_groups => { %{ setting('host_groups') }, pe => ['192.0.2.1'] },
     vrf_no_devicevrfs => { 'vendor:cisco' => 'vrf:blue', 'group:pe' => 'vrf:red' });
};

subtest 'vrf_skip_test__list_of_maps__each_applies' => sub {
  with_settings(sub {
    is_deeply(skipped_names($device, @names), ['red', 'blue'], 'both maps');
  }, vrf_no_devicevrfs => [ { '192.0.2.1' => 'vrf:red' }, { 'group:__ANY__' => 'vrf:blue' } ]);
};

subtest 'vrf_skip_test__default_table__never' => sub {
  with_settings(sub {
    is_deeply(skipped_names($device, 'default', '', 'red'), ['red'], 'only the named VRF');
  }, vrf_no_devicevrfs => { 'group:__ANY__' => ['vrf:.*', 'vrf:default', 'vrf:'] });
};

subtest 'vrf_skip_test__device_keys__matched_once_per_test' => sub {
  my $device_checks = 0;
  my $real = \&App::Netdisco::Util::VRF::acl_matches;
  no warnings 'redefine';
  local *App::Netdisco::Util::VRF::acl_matches = sub {
    $device_checks++ if ref $_[0] ne 'HASH';
    goto &$real;
  };
  with_settings(sub {
    my $skipped = vrf_skip_test($device);
    $skipped->("vrf$_") for (1 .. 50, 1 .. 50);
    is($device_checks, 2, 'one check per key, not per name');
  }, vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:vrf1.*', '192.0.2.1' => 'vrf:vrf2.*' });
};

subtest 'vrf_skip_test__bare_name_or_old_string__warns_once_and_skips_nothing' => sub {
  with_settings(sub {
    my @warnings = warnings_from(sub {
      is_deeply(skipped_names($device, @names), [], 'nothing skipped');
      skipped_names($device, @names);
    });
    is(scalar @warnings, 2, 'one warning each, not repeated');
    like($warnings[0], qr/"192\.0\.2\.1:red" is ignored/, 'old string entry');
    like($warnings[1], qr/rule "red" matches no VRF\. Write a VRF as vrf:<name>/, 'bare name');
  }, vrf_no_devicevrfs => [ '192.0.2.1:red', { 'group:__ANY__' => 'red' } ]);
};

subtest 'vrf_skip_test__empty_or_scalar_setting__nothing_skipped' => sub {
  for my $value ([], {}, undef, 'red') {
    with_settings(sub {
      is_deeply(skipped_names($device, @names), [], 'nothing skipped');
    }, vrf_no_devicevrfs => $value);
  }
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
  }, store_vrfs => 1, vrf_no_devicevrfs => { 'group:__ANY__' => ['vrf:MGMT', 'vrf:default'] });
};

subtest 'vrf_instances_for__incomplete_walk__still_returns_names' => sub {
  with_settings(sub {
    my $snmp = FakeSNMP->new(complete => 0, instances => { red => 'red' });
    is_deeply(vrf_instances_for($device, $snmp), { red => 'red' }, 'names');
  }, store_vrfs => 1);
};

# 3.985002 lists FRR's VRFs (snmp-info #685)
subtest 'build_pl__snmp_info_floor__3_985002' => sub {
  open my $fh, '<', 'Build.PL' or die "Build.PL: $!";
  my $text = do { local $/; <$fh> };
  like($text, qr/'SNMP::Info'\s*=>\s*'3\.985002'/, 'floor is 3.985002');
};

done_testing;
