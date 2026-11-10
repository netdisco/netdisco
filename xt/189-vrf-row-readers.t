#!/usr/bin/env perl

# Readers that must choose one row, or label one object, once the same address
# can exist in several VRFs: the default table (vrf = '') wins where one row is
# picked, and API objects carry their L3 domain. CI has no database, so the
# queries are checked as source text and the accessor runs on a stub handle.
# The audit subtest pins the readers deliberately left alone; a change to one
# of those lines needs a deliberate decision, not a silent drift.

use strict;
use warnings;

use Test::More 0.88;
use App::Netdisco::DB;

sub slurp {
  my $file = shift;
  open my $fh, '<', $file or die "$file: $!";
  local $/;
  return scalar <$fh>;
}

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $s = App::Netdisco::DB->clone;
  $s->storage_type('::DBI::Pg');
  $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $s;
};

# Replaces dbh_do so no connection is made; $queries collects what would run.
my @queries;
my $stub_row;
{
  no warnings qw/redefine once/;
  *DBIx::Class::Storage::DBI::dbh_do = sub {
    my ($storage, $code) = @_;
    my $dbh = bless {}, 'XtStubDbh';
    return $code->($storage, $dbh);
  };
  *XtStubDbh::selectrow_hashref = sub {
    my ($self, $sql, undef, @bind) = @_;
    push @queries, [ $sql, @bind ];
    return $stub_row;
  };
}

subtest 'nbtstat__ip_fallback__reads_default_vrf_rows_only' => sub {
  my $src = slurp('lib/App/Netdisco/Util/Nbtstat.pm');
  like($src, qr/search\(\s*\{\s*ip => \$ip, vrf => '', -bool => 'active' \}\s*,\s*\{\s*rows => 1 \}\s*\)\s*->first/s,
    "restricted to vrf = '', first row taken");
  unlike($src, qr/order_by => 'vrf'/, 'no ordering that could reach a VRF row');
  unlike($src, qr/->single\(\s*\{\s*ip => \$ip/, 'no single() on ip');
};

subtest 'nbtstat_core__polls__default_vrf_addresses_only' => sub {
  my $src = slurp('lib/App/Netdisco/Worker/Plugin/Nbtstat/Core.pm');
  like($src, qr/'me\.vrf'\s*=>\s*''/, "node_ip search is restricted to vrf = ''");
};

subtest 'subnet_typeahead__same_net_two_vrfs__suggested_once' => sub {
  my $src = slurp('lib/App/Netdisco/Web/TypeAhead.pm');
  my ($block) = $src =~ m{(ajax '/ajax/data/subnet/typeahead'.*?\n\};)}s;
  like($block, qr/columns => \['net'\],\s*distinct => 1/, 'distinct net');
};

subtest 'l3_domain_accessor__default_vrf__id_zero_empty_name_without_a_query' => sub {
  @queries = ();
  my %row = (
    NodeIp   => { mac => '00:11:22:33:44:55', ip => '10.0.0.1', vrf => '', router_last => '10.0.0.254' },
    DeviceIp => { ip => '10.0.0.254', alias => '10.0.0.1', vrf => '' },
    Subnet   => { net => '10.0.0.0/24', vrf => '', router_last => '10.0.0.254' },
  );
  foreach my $class (sort keys %row) {
    my $obj = $schema->resultset($class)->new_result($row{$class});
    is_deeply($obj->l3_domain, { id => 0, name => '' }, "$class default table");
    is_deeply($obj->TO_JSON->{l3_domain}, { id => 0, name => '' }, "$class TO_JSON carries it");
    ok(exists $obj->TO_JSON->{vrf}, "$class TO_JSON keeps its columns");
  }
  is(scalar @queries, 0, 'no query ran');
};

subtest 'l3_domain_accessor__named_vrf__one_query_returns_id_and_name' => sub {
  my %row = (
    NodeIp   => [ { mac => '00:11:22:33:44:55', ip => '10.0.0.1', vrf => 'RED', router_last => '10.0.0.254' }, '10.0.0.254' ],
    DeviceIp => [ { ip => '10.0.0.253', alias => '10.0.0.1', vrf => 'RED' }, '10.0.0.253' ],
    Subnet   => [ { net => '10.0.0.0/24', vrf => 'RED', router_last => '10.0.0.252' }, '10.0.0.252' ],
  );
  foreach my $class (sort keys %row) {
    my ($cols, $router) = @{ $row{$class} };
    @queries = ();
    $stub_row = { id => 7, name => 'RED' };
    my $obj = $schema->resultset($class)->new_result($cols);
    is_deeply($obj->l3_domain, { id => 7, name => 'RED' }, "$class returns id and name");
    is(scalar @queries, 1, "$class ran one query");
    like($queries[0][0], qr/l3_domain_of\(\?, \?\)/, "$class asks l3_domain_of");
    is_deeply([ @{ $queries[0] }[1,2] ], [ $router, 'RED' ], "$class binds router and vrf");
  }

  $stub_row = undef;
  my $unknown = $schema->resultset('NodeIp')->new_result(
    { mac => '00:11:22:33:44:55', ip => '10.0.0.1', vrf => 'RED' });
  is($unknown->l3_domain, undef, 'NULL domain gives undef');
  is($queries[-1][1], undef, 'undef router_last binds NULL');
  ok(exists $unknown->TO_JSON->{l3_domain}, 'TO_JSON still has the key');
};

subtest 'audit__left_as_they_are__unchanged' => sub {
  my %audited = (
    'lib/App/Netdisco/Web/Plugin/Device/Ports.pm' =>
      [ 'FROM node_ip WHERE mac = n.mac AND active = n.active) i ON true' ],
    'lib/App/Netdisco/DB/ResultSet/Node.pm' =>
      [ 'SELECT 1 FROM device_ip di WHERE di.alias = device_port.remote_ip' ],
    'lib/App/Netdisco/DB/Result/Virtual/UndiscoveredNeighbors.pm' =>
      [ 'AND ((p.remote_ip NOT IN (SELECT alias FROM device_ip))' ],
    'lib/App/Netdisco/Web/Plugin/Device/Details.pm' =>
      [ 'my @interfaces = $device->device_ips->hri->all;' ],
    'lib/App/Netdisco/Worker/Plugin/Expire.pm' =>
      [ "schema('netdisco')->resultset('NodeIp')->search({",
        "mac => { -in => schema('netdisco')->resultset('NodeIp')->search(" ],
    'lib/App/Netdisco/Util/Statistics.pm' =>
      [ "\$schema->resultset('DeviceIp')->count_rs->as_query,",
        "\$schema->resultset('NodeIp')->count_rs->as_query," ],
    'lib/App/Netdisco/Web/Metrics.pm' =>
      [ "my \$count = try { schema(\$tenant)->resultset('NodeIp')->count } catch { 0 };" ],
    'lib/App/Netdisco/Web/Plugin/Report/DeviceAddrNoDNS.pm' =>
      [ "{ 'device_ips.dns' => undef }," ],
  );
  foreach my $file (sort keys %audited) {
    my $src = slurp($file);
    foreach my $line (@{ $audited{$file} }) {
      ok(index($src, $line) >= 0, "$file: $line");
    }
  }
};

done_testing;
