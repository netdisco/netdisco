#!/usr/bin/env perl

use strict;
use warnings;

# Discover and CLI arpnip recompute L3 domains only when something the
# recompute reads may have changed: the device's own evidence (decided by the
# caller), a configured vrf_domains, a manual member row left behind, or a
# domain key from before evidence keys. Arpnip runs hourly, so it leaves the
# configured reasons to the daily discover and recomputes only on its own change or a repair. The recompute holds a network-wide lock
# for 0.3-0.7 s at 10k named VRF rows, and a poller recycles after every job,
# so nothing can be remembered between runs. Only the database handle is
# faked; the SQL itself is run against PostgreSQL by hand (see the task report).

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Util::L3Domain qw/l3_domain_recompute_needed/;
use Dancer qw/:script !pass/;

my (@queries, %answers);

package FakeDbh;
sub new { return bless {}, $_[0] }
sub selectrow_array {
  my ($self, $sql) = @_;
  push @queries, $sql;
  for my $pattern (keys %answers) {
    return $answers{$pattern} if $sql =~ /$pattern/;
  }
  return 0;
}

package FakeStorage;
sub dbh_do { my ($self, $code) = @_; return $code->($self, FakeDbh->new) }

package FakeSchema;
sub new { return bless {}, shift }
sub storage { return bless {}, 'FakeStorage' }

package main;

sub needed {
  my ($changed, %settings) = @_;
  @queries = ();
  my $saved = setting('vrf_domains');
  set(vrf_domains => $settings{vrf_domains} // []);
  my $result = l3_domain_recompute_needed(FakeSchema->new, $changed, $settings{arpnip});
  set(vrf_domains => $saved);
  return $result;
}

subtest 'recompute_needed__device_changed__true_without_sql' => sub {
  %answers = ();
  ok needed(1), 'true';
  is scalar(@queries), 0, 'no SQL ran';
};

subtest 'recompute_needed__unchanged_no_config_no_manual__false' => sub {
  %answers = ();
  ok !needed(0), 'false';
  is scalar(@queries), 5, 'the four database checks ran';
};

subtest 'recompute_needed__vrf_domains_set__true' => sub {
  %answers = ();
  ok needed(0, vrf_domains => [ { domain => 'core', device => '192.0.2.1', vrf => 'red' } ]), 'true';
  is scalar(@queries), 0, 'no SQL needed';
};

subtest 'recompute_needed__vrf_domains_malformed_hash__true' => sub {
  %answers = ();
  ok needed(0, vrf_domains => { domain => 'core' }), 'a hash is set, so the recompute runs and warns';
  is scalar(@queries), 0, 'no SQL needed';
  ok !needed(0, vrf_domains => {}), 'an empty hash is not set';
};

subtest 'recompute_needed__manual_rows_left__true' => sub {
  %answers = ("source = 'manual'" => 1);
  ok needed(0), 'true';
};

subtest 'recompute_needed__legacy_key__true' => sub {
  %answers = ('inferred_name !~' => 1);
  ok needed(0), 'true';
  like $queries[-1], qr/id <> 0/, 'domain 0 is excluded';
};

# a legacy key is the bare VRF name, which may itself hold a colon, so the
# test is for the evidence prefixes rather than for any colon
subtest 'recompute_needed__legacy_key_with_colon__detected_by_prefix' => sub {
  %answers = ('inferred_name !~' => 1);
  needed(0);
  like $queries[-1], qr/inferred_name !~ '\^\(isid\|rt\|name\|manual\):'/, 'every key prefix listed';
  unlike $queries[-1], qr/position\(/, 'not a test for any colon';
};

subtest 'recompute_needed__vrf_without_member__true' => sub {
  %answers = ('FROM device_vrf d' => 1);
  ok needed(0), 'true';
  like $queries[-1], qr/d\.vrf <> ''/, 'named VRFs only';
};

subtest 'recompute_needed__member_without_vrf__true' => sub {
  %answers = ('FROM l3_domain_member m WHERE NOT EXISTS' => 1);
  ok needed(0), 'true';
};

subtest 'recompute_needed__empty_domain__true' => sub {
  %answers = ('FROM l3_domain d WHERE d\.id <> 0\s+AND NOT EXISTS' => 1);
  ok needed(0), 'true';
};

subtest 'recompute_needed__all_placed__false' => sub {
  %answers = ();
  ok !needed(0), 'false, the legacy check included';
  ok scalar(grep { /inferred_name !~/ } @queries), 'legacy key check ran';
};

subtest 'recompute_needed__arpnip_vrf_domains_set__false' => sub {
  %answers = ();
  ok !needed(0, arpnip => 1, vrf_domains => [ { domain => 'core', device => '192.0.2.1', vrf => 'red' } ]),
    'the setting is left to discover';
  is scalar(@queries), 4, 'the repair checks ran';
};

subtest 'recompute_needed__arpnip_manual_rows_left__false' => sub {
  %answers = ("source = 'manual'" => 1);
  ok !needed(0, arpnip => 1), 'manual rows are left to discover';
  ok !scalar(grep { /source = 'manual'/ } @queries), 'not even checked';
};

subtest 'recompute_needed__arpnip_device_changed__true_without_sql' => sub {
  %answers = ();
  ok needed(1, arpnip => 1), 'true';
  is scalar(@queries), 0, 'no SQL ran';
};

subtest 'recompute_needed__arpnip_vrf_without_member__true' => sub {
  %answers = ('FROM device_vrf d' => 1);
  ok needed(0, arpnip => 1), 'a repair still runs';
};

done_testing;
