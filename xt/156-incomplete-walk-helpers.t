#!/usr/bin/env perl

use strict; use warnings;

# SNMP::Info records every table walk that ends early in walk_failures. One
# SNMP::Info object serves a whole job, so the list grows across workers:
# each worker takes a mark before its reads and looks only at what came after
# it. Objects without the record (offline snapshots, test fakes) report none.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Util::SNMP
  qw/walk_mark incomplete_walks incomplete_walk_message/;

package FakeRecord;
sub new { my ($class, %vals) = @_; return bless {%vals}, $class }
sub walk_failures { $_[0]{failures} ||= [] }
sub walk_status { $_[0]{status} ||= {} }

package main;

my $device = App::Netdisco::DB->resultset('Device')
  ->new_result({ ip => '192.0.2.1' });

my %fdb_timeout = (
  method => 'fw_mac', leaf => 'BRIDGE-MIB::dot1dTpFdbAddress',
  reason => 'timeout', rows => 40, walk => 'bulkwalk', repeaters => 10,
  context => '20',
);
my %ifindex_loop = (
  method => 'i_index', leaf => 'IF-MIB::ifIndex', reason => 'loop',
  rows => 7, walk => 'getnext', repeaters => undef, context => '',
);

subtest 'walk_mark__three_failures__returns_3' => sub {
  my $snmp = FakeRecord->new(failures => [{%fdb_timeout}, {%fdb_timeout},
    {%ifindex_loop}]);
  is walk_mark($snmp), 3, 'mark is the failure count';
};

subtest 'incomplete_walks__failures_before_mark__are_ignored' => sub {
  my $snmp = FakeRecord->new(failures => [{%fdb_timeout}]);
  my $mark = walk_mark($snmp);
  push @{ $snmp->walk_failures }, {%ifindex_loop};
  is_deeply [incomplete_walks($snmp, $mark)], [{%ifindex_loop}],
    'only the failure after the mark';
};

subtest 'incomplete_walks__object_without_walk_failures__returns_empty_list'
  => sub {
  my $snmp = bless {}, 'NoRecord';
  is walk_mark($snmp), 0, 'mark is 0';
  is_deeply [incomplete_walks($snmp, 0)], [], 'no failures';
};

subtest 'incomplete_walks__absent_outcome_in_walk_status_only__returns_empty_list'
  => sub {
  my $snmp = FakeRecord->new(status => { i_vlan => {
    method => 'i_vlan', leaf => 'CISCO-VLAN-MEMBERSHIP-MIB::vmVlan',
    complete => 1, reason => 'absent', rows => 0, walk => 'bulkwalk',
  }});
  is_deeply [incomplete_walks($snmp, 0)], [], 'absent is not a failure';
};

subtest
  'incomplete_walk_message__bulkwalk_in_vlan_context__names_table_reason_method_and_context'
  => sub {
  is incomplete_walk_message($device, 'macsuck', {%fdb_timeout}),
    '[192.0.2.1] macsuck - kept existing rows, incomplete SNMP walk: fw_mac'
    . ' (BRIDGE-MIB::dot1dTpFdbAddress) timeout after 40 rows by bulkwalk'
    . ' with 10 repeaters in context 20',
    'message names everything';
};

subtest 'incomplete_walk_message__getnext_default_context__omits_repeaters_and_context'
  => sub {
  is incomplete_walk_message($device, 'interfaces', {%ifindex_loop},
    {%fdb_timeout}),
    '[192.0.2.1] interfaces - kept existing rows, incomplete SNMP walk:'
    . ' i_index (IF-MIB::ifIndex) loop after 7 rows by getnext;'
    . ' fw_mac (BRIDGE-MIB::dot1dTpFdbAddress) timeout after 40 rows by'
    . ' bulkwalk with 10 repeaters in context 20',
    'getnext outcome has no repeaters or context, outcomes joined by "; "';
};

done_testing;
