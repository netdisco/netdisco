#!/usr/bin/env perl

use strict;
use warnings;

# Every address-to-device lookup goes through resolve_alias or the
# device_ip_resolved view, so an address reused in two VRFs never picks a
# device arbitrarily. Existence checks stay on device_ip: any VRF counts.

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Path::Tiny ();
use App::Netdisco;
use Dancer ':tests';
use App::Netdisco::DB;

set logger => 'null';

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  App::Netdisco::DB->clone;
};

my $virtual = 'lib/App/Netdisco/DB/Result/Virtual';

subtest 'get_device__uses_resolve_alias__not_find_with_two_keys' => sub {
  my $src = Path::Tiny::path('lib/App/Netdisco/Util/Device.pm')->slurp_utf8;
  like $src, qr/resolve_alias\(\$ip\)/, 'calls resolve_alias';
  unlike $src, qr/resultset\('DeviceIp'\)->find\(/, 'no find on DeviceIp';
};

{
  package FakeRow;
  sub ip { $_[0]{ip} }

  package FakeRs;
  our $LOG;
  sub search { my ($self, $cond) = @_; push @$LOG, [ $self->{name}, $cond ]; $self }
  sub first { $_[0]{row} }
  sub result_source { $_[0] }
  sub schema { $_[0] }
  sub resultset { die "unexpected $_[1]" unless $_[1] eq 'DeviceIpResolved'; $_[0]{view} }
}

sub resolve_with {
  my ($own, $viewed, $log) = @_;
  local $FakeRs::LOG = $log;
  my $view_rs = bless { name => 'view', row => $viewed }, 'FakeRs';
  my $own_rs  = bless { name => 'own', row => $own, view => $view_rs }, 'FakeRs';
  return App::Netdisco::DB::ResultSet::DeviceIp::resolve_alias($own_rs, '192.0.2.1');
}

sub row { bless { ip => $_[0] }, 'FakeRow' }

subtest 'resolve_alias__own_address__searched_before_view' => sub {
  my @log;
  my $got = resolve_with(row('192.0.2.1'), row('198.51.100.9'), \@log);
  is $got, '192.0.2.1', 'own row wins';
  is scalar @log, 1, 'view never searched';
  is_deeply $log[0][1], { ip => '192.0.2.1', alias => '192.0.2.1' }, 'own-address search';
};

subtest 'resolve_alias__no_own_row__reads_device_ip_resolved' => sub {
  my @log;
  is resolve_with(undef, row('198.51.100.9'), \@log), '198.51.100.9', 'view row';
  is_deeply [ map { $_->[0] } @log ], [qw(own view)], 'own first, then view';
  is_deeply $log[1][1], { alias => '192.0.2.1' };

  @log = ();
  is resolve_with(undef, undef, \@log), undef, 'unknown address gives undef';
};

subtest 'address_to_device_joins__use_device_ip_resolved' => sub {
  for my $class (qw(UnDirEdgesAgg DeviceLinks OrphanedDevices DuplexMismatch
                    PortVLANMismatch NodesDiscovered ACLEntriesWithDNS)) {
    my $src = Path::Tiny::path("$virtual/$class.pm")->slurp_utf8;
    like $src, qr/device_ip_resolved/, "$class reads the view";
    unlike $src, qr/JOIN device_ip /, "$class has no JOIN device_ip";
    unlike $src, qr/FROM device_ip a\b/, "$class has no FROM device_ip a";
  }
  my $links = Path::Tiny::path("$virtual/DeviceLinks.pm")->slurp_utf8;
  like $links, qr/FROM device_ip_resolved GROUP BY alias HAVING count\(alias\) = 1/,
    'DeviceLinks keeps its one-device condition against the view';
};

subtest 'existence_checks__still_read_device_ip' => sub {
  like Path::Tiny::path("$virtual/UndiscoveredNeighbors.pm")->slurp_utf8, qr/device_ip\b(?!_resolved)/;
  unlike Path::Tiny::path("$virtual/UndiscoveredNeighbors.pm")->slurp_utf8, qr/device_ip_resolved/;
  my $node = Path::Tiny::path('lib/App/Netdisco/DB/ResultSet/Node.pm')->slurp_utf8;
  unlike $node, qr/DeviceIpResolved|device_ip_resolved/, 'Node.pm untouched';
};

subtest 'canonical_ip__device_identity__default_vrf_candidates_only' => sub {
  like Path::Tiny::path('lib/App/Netdisco/Worker/Plugin/Discover/CanonicalIP.pm')->slurp_utf8,
    qr/device_ips->search\(\{ vrf => '' \}\)/, 'candidates filtered to default VRF';
};

subtest 'neighbor_alias_and_graph__read_device_ip_resolved' => sub {
  like Path::Tiny::path('lib/App/Netdisco/DB/Result/DevicePort.pm')->slurp_utf8,
    qr/resultset\('DeviceIpResolved'\)/, 'neighbor_alias subquery';
  like Path::Tiny::path('lib/App/Netdisco/Util/Graph.pm')->slurp_utf8,
    qr/resultset\('DeviceIpResolved'\)/, 'graph aliases';
};

subtest 'neighbor_alias__generated_sql__pins_foreign_row_to_resolved_device' => sub {
  my $offline = App::Netdisco::DB->connect('dbi:Pg:dbname=none', 'u', 'p');
  my $rs = $offline->resultset('DevicePort')->search({},
    { join => 'neighbor_alias', columns => ['neighbor_alias.ip'] });
  my ($sql) = @{ ${ $rs->as_query } };
  like $sql, qr/neighbor_alias\.alias\s*=\s*\(\s*SELECT/, 'alias from resolved subquery';
  like $sql, qr/neighbor_alias\.ip\s*=\s*\(\s*SELECT/, 'ip pinned, not alias-only';
  like $sql, qr/neighbor_alias\.vrf\s*=\s*\(SELECT min\(devipvrf\.vrf\)/, 'one VRF row';
  like $sql, qr/device_ip_resolved/, 'subquery reads the view';
  is scalar(() = $sql =~ /ORDER BY ip LIMIT/g), 2, 'both subqueries ordered, so they agree';
};

done_testing;
