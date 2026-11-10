#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Util::Node ();
use Dancer qw/:script !pass/;

# L3 domains are built from device_vrf, which SNMP discover writes. A VRF that
# a CLI collector reads but SNMP::Info does not list (NX-OS management, for
# one) had no row, so its ARP entries and subnets had no domain and the
# domain-grouped reports left them out. CLI arpnip now records the VRFs it
# read, without touching what discover recorded.

# A device_vrf result set that records what it is asked to do. CI has no
# database.
package FakeVrfRS;
sub new { my ($class, %vals) = @_; return bless { calls => [], stored => [], changed => 1, %vals }, $class }
sub upsert {
  my ($self, $rows, $options) = @_;
  push @{ $self->{calls} }, [ upsert => [ map { {%$_} } @$rows ], $options ];
  return (scalar @$rows ? $self->{changed} : 0);
}
sub search {
  my ($self, $cond) = @_;
  push @{ $self->{calls} }, [ search => $cond ];
  my $rs = $self;
  return bless { parent => $rs, cond => $cond }, 'FakeVrfSearch';
}
package FakeVrfSearch;
sub delete {
  my $self = shift;
  my $cond = $self->{cond};
  my %keep = map { ($_ => 1) } @{ $cond->{vrf}{-not_in} || [] };
  my @gone = grep { $_->{ip} eq $cond->{ip} and $_->{listed_by} eq $cond->{listed_by}
                    and not $keep{ $_->{vrf} } } @{ $self->{parent}{stored} };
  push @{ $self->{parent}{deleted} }, map { $_->{vrf} } @gone;
  return (scalar @gone || '0E0');
}
package FakeSchema;
sub new { my ($class, $rs) = @_; return bless { rs => $rs }, $class }
sub resultset { $_[0]{rs} }

package main;

my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });

# what xt/213 covers: the repair checks asked of the database
our $other_reason_to_recompute = 0;
our @needed_args;

sub record {
  my ($rs, $vrf_read, $list_complete) = @_;
  my $recomputed = 0;
  no warnings 'redefine';
  local *App::Netdisco::Util::Node::schema = sub { FakeSchema->new($rs) };
  local *App::Netdisco::Util::Node::l3_domain_recompute_needed = sub { @needed_args = @_; $_[1] || $other_reason_to_recompute };
  local *App::Netdisco::Util::Node::recompute_l3_domains = sub { $recomputed++; 0 };
  my $changed = App::Netdisco::Util::Node::record_cli_vrfs($device, $vrf_read, $list_complete, 'LOCALTIMESTAMP');
  return ($changed, $recomputed);
}

sub upserts { grep { $_->[0] eq 'upsert' } @{ $_[0]{calls} } }

subtest 'record_cli_vrfs__vrf_read__rows_inserted_listed_by_cli' => sub {
  my $rs = FakeVrfRS->new;
  my ($changed, $recomputed) = record($rs, { '' => 1, red => 1, management => 0 }, 0);
  my ($upsert) = upserts($rs);
  is_deeply([ map { $_->{vrf} } @{ $upsert->[1] } ], [qw/management red/], 'one row per named VRF, never the default table');
  my %row = %{ $upsert->[1][0] };
  is($row{ip}, '192.0.2.1', 'for this device');
  is($row{kind}, 'vrf', 'kind vrf');
  is($row{listed_by}, 'cli', 'listed by the CLI');
  is($row{complete}, 0, 'management was not read whole');
  is($upsert->[1][1]{complete}, 1, 'red was');
  is_deeply([ sort @{ $upsert->[2]{insert_only} } ],
    [ sort grep { $_ ne 'ip' and $_ ne 'vrf' } keys %row ],
    'every non-key column insert-only, so a row discover wrote keeps its facts');
  is($recomputed, 1, 'domains recomputed once');
  ok($changed, 'reports a change');
};

subtest 'record_cli_vrfs__list_whole__stale_cli_rows_deleted_only' => sub {
  my $rs = FakeVrfRS->new(changed => 0, stored => [
    { ip => '192.0.2.1', vrf => 'management', listed_by => 'cli' },
    { ip => '192.0.2.1', vrf => 'old',        listed_by => 'cli' },
    { ip => '192.0.2.1', vrf => 'gone',       listed_by => 'snmp' },
  ]);
  my (undef, $recomputed) = record($rs, { management => 1 }, 1);
  is_deeply($rs->{deleted}, ['old'], 'only the CLI row no longer read is deleted');
  is($recomputed, 1, 'domains recomputed after the delete');
};

subtest 'record_cli_vrfs__list_partial__nothing_deleted' => sub {
  my $rs = FakeVrfRS->new(changed => 0, stored => [ { ip => '192.0.2.1', vrf => 'old', listed_by => 'cli' } ]);
  my (undef, $recomputed) = record($rs, { management => 1 }, 0);
  ok(!(grep { $_->[0] eq 'search' } @{ $rs->{calls} }), 'no delete issued');
  is($recomputed, 0, 'nothing changed, no recompute');
};

subtest 'record_cli_vrfs__nothing_changed__no_recompute' => sub {
  my $rs = FakeVrfRS->new(changed => 0);
  my ($changed, $recomputed) = record($rs, { red => 1 }, 1);
  is($recomputed, 0, 'no recompute');
  ok(!$changed, 'reports no change');
};

subtest 'arpnip__cli_vrfs_unchanged_but_repair_needed__recompute' => sub {
  local $other_reason_to_recompute = 1;
  my $rs = FakeVrfRS->new(changed => 0);
  my ($changed, $recomputed) = record($rs, { red => 1 }, 1);
  is($recomputed, 1, 'recomputed although no row changed');
  ok(!$changed, 'still reports no row change');
};

subtest 'arpnip__recompute_gate__asked_as_arpnip' => sub {
  my $rs = FakeVrfRS->new(changed => 0);
  record($rs, { red => 1 }, 1);
  ok($needed_args[2], 'vrf_domains and manual rows are left to discover');
};

subtest 'record_cli_vrfs__no_vrf_read__no_upsert' => sub {
  my $rs = FakeVrfRS->new(changed => 0);
  record($rs, { '' => 1 }, 0);
  is(scalar(upserts($rs)), 0, 'nothing to record');
};

# the arpnip worker and discover
my $nodes = do { local (@ARGV, $/) = 'lib/App/Netdisco/Worker/Plugin/Arpnip/Nodes.pm'; <> };
my $properties = do { local (@ARGV, $/) = 'lib/App/Netdisco/Worker/Plugin/Discover/Properties.pm'; <> };

subtest 'arpnip__cli_vrf_list__saved_by_the_cli_worker_and_reset_each_job' => sub {
  like($nodes, qr/vars->\{'cli_vrf_list'\} = \{ read => \{ %vrf_read \}, complete => \$list_complete \}/,
    'the CLI worker saves what it read');
  like($nodes, qr/delete \@\{ vars\(\) \}\{qw\/[^\/]*\bcli_vrf_list\b[^\/]*\/\}/, 'reset in early with the other VRF keys');
};

# the store phase's call, its arguments and its failure handling: xt/197

subtest 'discover__cli_listed_vrfs__kept_by_remove_unseen' => sub {
  like($properties, qr/_cli_listed_vrfs\(\$device\)/, 'discover reads the CLI-listed VRFs');
  like($properties, qr/grep \{ \(\$_->\{listed_by\} \/\/ ''\) eq 'cli' \}\s*\n\s*\$device->vrfs\(/,
    'only rows listed by the CLI');
  like($properties, qr/my \@vrf_seen = \(\(map \{\{ vrf => \$_->\{vrf\} \}\} \@vrf_rows\),\s*map \{\{ vrf => \$_ \}\} sort keys %stored_vrfs, _cli_listed_vrfs\(\$device\)\);/,
    'and counts them as seen, so remove_unseen keeps them');
};

done_testing;
