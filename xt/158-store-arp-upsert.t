#!/usr/bin/env perl

use strict;
use warnings;

# store_arp wrote each ARP entry three times: the retire step hit the target
# row too, then update_or_new and the router maps each wrote a new version,
# none HOT while GIN indexes covered the maps. It now locks the IP, retires
# every other active binding of that IP, and upserts once.
#
# Excluding the target row from the retire is what lets two pollers that
# report one IP under different MACs deadlock, so the lock must come first
# and must hash one spelling per address.
#
# Only the database handle is faked; these check the SQL and binds sent.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use App::Netdisco;
use Dancer ':tests';
use App::Netdisco::Util::Node 'store_arp';

set logger => 'null';

my (@ran, $txns);

package FakeDbh;
sub new { return bless {}, $_[0] }
sub do  { my ($self, $sql, undef, @binds) = @_; push @ran, [$sql, @binds]; return 1 }

package FakeSchema;
sub new     { return bless { dbh => FakeDbh->new }, $_[0] }
sub txn_do  { ++$txns; return $_[1]->() }
sub storage { return $_[0] }
sub dbh_do  { my ($self, $code) = @_; return $code->($self, $self->{dbh}) }

package main;

{ no warnings 'redefine'; *App::Netdisco::Util::Node::schema = sub { FakeSchema->new }; }

sub run_store {
  @ran = (); $txns = 0;
  store_arp(@_);
  return @ran;
}

my %host = (ip => '192.0.2.1', node => '00:11:22:33:44:55', dns => 'host.example.com');
my $now = 'to_timestamp(1.5)::timestamp';

subtest 'store_arp__statement_order__lock_retire_upsert' => sub {
  my @stmts = run_store({%host}, $now, '198.51.100.1');
  is(scalar @stmts, 3, 'three statements');
  like($stmts[0][0], qr/pg_advisory_xact_lock/, 'lock first');
  like($stmts[1][0], qr/^\s*UPDATE node_ip SET active = false/, 'retire second');
  like($stmts[2][0], qr/INSERT INTO node_ip/, 'upsert last');
  is($txns, 1, 'one transaction');
};

subtest 'store_arp__lock__hashes_inet_normalized_ip' => sub {
  my ($lock) = run_store({%host, ip => '2001:db8::1'}, $now, '198.51.100.1');
  like($lock->[0], qr/hashtext\(host\(\?::inet\)\)/);
  is_deeply([@$lock[1 .. $#$lock]], [1728, '2001:db8::1']);
};

subtest 'store_arp__retire__excludes_only_the_target' => sub {
  my (undef, $retire) = run_store({%host}, $now, '198.51.100.1');
  like($retire->[0], qr/WHERE ip = \? AND active AND NOT \(mac = \? AND vrf = \?\)/);
  is_deeply([@$retire[1 .. $#$retire]], ['192.0.2.1', '00:11:22:33:44:55', '']);
};

subtest 'store_arp__upsert__conflict_key_and_columns' => sub {
  my (undef, undef, $upsert) = run_store({%host}, $now, '198.51.100.1');
  my $sql = $upsert->[0];
  like($sql, qr/ON CONFLICT \(mac, ip, vrf\) DO UPDATE/);
  my ($update) = $sql =~ /DO UPDATE(.*)\z/s;
  like($update, qr/active = true/);
  like($update, qr/dns = EXCLUDED\.dns/);
  like($update, qr/time_last = EXCLUDED\.time_last/);
  unlike($update, qr/time_first/, 'time_first only on insert');
  ok(index($sql, $now) >= 0, 'job time interpolated');
};

subtest 'store_arp__with_device_ip__writes_both_router_maps' => sub {
  my (undef, undef, $upsert) = run_store({%host}, $now, '198.51.100.1');
  my ($sql, @binds) = @$upsert;
  is(scalar(grep { $_ eq '198.51.100.1' } @binds), 3, 'router in both new maps and the first-seen test');
  is(scalar(grep { $_ eq '{198.51.100.1}' } @binds), 2, 'router path for both jsonb_set calls');
  my ($update) = $sql =~ /DO UPDATE(.*)\z/s;
  like($update, qr/seen_on_router_last = jsonb_set\(n\.seen_on_router_last/);
  like($update, qr/seen_on_router_first = CASE WHEN \(n\.seen_on_router_first -> \?\) IS NOT NULL/);
};

subtest 'store_arp__without_device_ip__leaves_router_maps_alone' => sub {
  my @stmts = run_store({%host});
  my ($sql) = @{ $stmts[2] };
  like($sql, qr/LOCALTIMESTAMP/);
  is(scalar(() = $sql =~ /'\{\}'::jsonb/g), 2, 'empty maps on insert');
  my ($update) = $sql =~ /DO UPDATE(.*)\z/s;
  unlike($update, qr/seen_on_router/);
};

subtest 'store_arp__with_vrf__binds_vrf_in_key_and_exclusion' => sub {
  my (undef, $retire, $upsert) = run_store({%host, vrf => 'blue'}, $now, '198.51.100.1');
  is($retire->[-1], 'blue', 'retire exclusion');
  ok(scalar(grep { defined and $_ eq 'blue' } @$upsert[1 .. $#$upsert]), 'upsert key');
};

subtest 'store_arp__bad_mac__writes_nothing' => sub {
  my @stmts = run_store({%host, node => 'zz'}, $now, '198.51.100.1');
  is(scalar @stmts, 0);
};

done_testing;
