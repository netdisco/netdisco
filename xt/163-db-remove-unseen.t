#!/usr/bin/env perl

# remove_unseen is a data-loss and security boundary: a DELETE that is too
# broad removes other devices' rows. Real result sources are used with a fake
# database handle, so these assert the SQL and binds sent, and that bad input
# dies before anything is sent.

use strict;
use warnings;

use Test::More 0.88;
use App::Netdisco::DB;

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $s = App::Netdisco::DB->clone;
  $s->storage_type('::DBI::Pg');
  $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $s;
};

my (@ran, @counts);

package FakeDbh;
sub do {
  my ($self, $sql, undef, @binds) = @_;
  push @ran, [$sql, @binds];
  return @counts ? shift @counts : 1;
}
sub quote_identifier { return '"' . ($_[1] =~ s/"/""/gr) . '"' }

package main;

my $fake = bless {}, 'FakeDbh';
no warnings qw(redefine once);
local *DBIx::Class::Storage::DBI::dbh_do = sub { my ($s, $code) = @_; $code->($s, $fake) };

my $delete_sql = 'DELETE FROM "device_port_vlan" WHERE "ip" = ? AND ("port", "vlan", "native")'
  . ' NOT IN (SELECT * FROM unnest(?::text[], ?::integer[], ?::boolean[]))';

sub remove_ok {
  my ($source, $scope, $seen) = @_;
  @ran = ();
  return $schema->resultset($source)->remove_unseen($scope, $seen);
}

sub remove_dies_like {
  my ($source, $scope, $seen, $regex, $name) = @_;
  @ran = ();
  my $ok = eval { $schema->resultset($source)->remove_unseen($scope, $seen); 1 };
  my $error = $@;
  ok(!$ok, "$name: dies");
  like($error, $regex, "$name: message");
  is(scalar @ran, 0, "$name: nothing sent");
}

subtest 'remove_unseen__seen_keys__one_delete_with_array_binds' => sub {
  @counts = (2);
  my $deleted = remove_ok('DevicePortVlan', { ip => '192.0.2.1' },
    [ { port => 'Gi1/1', vlan => 10, native => 1 }, { port => 'Gi1/2', vlan => 20, native => 0 } ]);
  is($deleted, 2, 'returns the rows deleted');
  is(scalar @ran, 1, 'one statement');
  is($ran[0][0], $delete_sql, 'sql');
  is_deeply([ @{$ran[0]}[1 .. $#{$ran[0]}] ],
    ['192.0.2.1', ['Gi1/1', 'Gi1/2'], [10, 20], [1, 0]], 'binds');
};

subtest 'remove_unseen__nothing_seen__deletes_whole_scope' => sub {
  remove_ok('DevicePortVlan', { ip => '192.0.2.1' }, []);
  is(scalar @ran, 1, 'one statement');
  is($ran[0][0], $delete_sql, 'sql');
  is_deeply([ @{$ran[0]}[1 .. $#{$ran[0]}] ], ['192.0.2.1', [], [], []], 'binds');
};

subtest 'remove_unseen__hostile_value__bound_verbatim' => sub {
  my $hostile = q{x'); DROP TABLE device; --};
  remove_ok('DevicePortVlan', { ip => '192.0.2.1' }, [ { port => $hostile, vlan => 1, native => 0 } ]);
  unlike($ran[0][0], qr/DROP TABLE/, 'absent from the SQL text');
  is_deeply($ran[0][2], [$hostile], 'sent as a bind, unchanged');
};

subtest 'remove_unseen__reserved_column_name__quoted' => sub {
  remove_ok('DeviceModule', { ip => '192.0.2.1' }, [ { index => 1 } ]);
  is($ran[0][0], 'DELETE FROM "device_module" WHERE "ip" = ? AND ("index")'
    . ' NOT IN (SELECT * FROM unnest(?::integer[]))', 'quoted');
};

subtest 'remove_unseen__empty_scope__dies' => sub {
  remove_dies_like('DevicePortVlan', {}, [],
    qr/remove_unseen: scope must name at least one key column of 'device_port_vlan'/, 'empty scope');
};

subtest 'remove_unseen__scope_outside_key__dies' => sub {
  remove_dies_like('DeviceVlan', { description => 'x' }, [],
    qr/remove_unseen: scope column 'description' is not a primary key column of 'device_vlan'/, 'non-key column');
  remove_dies_like('DeviceVlan', { 'ip; --' => 1 }, [],
    qr/remove_unseen: scope column 'ip; --' is not a primary key column/, 'hostile column');
};

subtest 'remove_unseen__scope_covers_whole_key__dies' => sub {
  remove_dies_like('Subnet', { net => '192.0.2.0/24' }, [],
    qr/remove_unseen: scope covers the whole key/, 'single-column key');
  remove_dies_like('DeviceVlan', { ip => '192.0.2.1', vlan => 10 }, [],
    qr/remove_unseen: scope covers the whole key/, 'multi-column key');
};

subtest 'remove_unseen__seen_row_wrong_columns__dies' => sub {
  my $scope = { ip => '192.0.2.1' };
  remove_dies_like('DevicePortVlan', $scope,
    [ { port => 'a', vlan => 1, native => 0 }, { port => 'a', vlan => 2 } ],
    qr/remove_unseen: seen row 1 has columns \(port, vlan\) but must have exactly \(native, port, vlan\)/, 'missing');
  remove_dies_like('DevicePortVlan', $scope,
    [ { port => 'a', vlan => 1, native => 0, description => 'x' } ],
    qr/remove_unseen: seen row 0 has columns \(description, native, port, vlan\) but must have exactly/, 'extra');
  remove_dies_like('DevicePortVlan', $scope, ['x'],
    qr/remove_unseen: seen row 0 is not a hash reference/, 'not a hash');
  remove_dies_like('DevicePortVlan', $scope, { port => 'a' },
    qr/remove_unseen: seen must be an array reference/, 'not an array');
};

subtest 'remove_unseen__ref_values__die' => sub {
  my $good = { port => 'a', vlan => 1, native => 0 };
  foreach my $ref ([1], { a => 1 }, sub {}, \'x', \'LOCALTIMESTAMP') {
    remove_dies_like('DevicePortVlan', { ip => $ref }, [],
      qr/remove_unseen: scope value for 'ip' must be a plain scalar/, 'scope ' . ref $ref);
    remove_dies_like('DevicePortVlan', { ip => '192.0.2.1' }, [ { %$good, vlan => $ref } ],
      qr/remove_unseen: seen row 0 value for 'vlan' must be a plain scalar/, 'seen ' . ref $ref);
  }
  remove_dies_like('DevicePortVlan', { ip => undef }, [],
    qr/remove_unseen: scope value for 'ip' must be a plain scalar/, 'undef scope');
  remove_dies_like('DevicePortVlan', { ip => '192.0.2.1' }, [ { %$good, vlan => undef } ],
    qr/remove_unseen: seen row 0 value for 'vlan' must be a plain scalar/, 'undef seen');
};

subtest 'remove_unseen__bad_arguments__die' => sub {
  remove_dies_like('DevicePortVlan', undef, [], qr/remove_unseen: scope must be a hash reference/, 'undef scope');
  remove_dies_like('DevicePortVlan', ['ip'], [], qr/remove_unseen: scope must be a hash reference/, 'array scope');
  remove_dies_like('DevicePortVlan', { ip => '192.0.2.1' }, undef, qr/remove_unseen: seen must be an array reference/, 'undef seen');
};

subtest 'remove_unseen__unsafe_data_type__dies' => sub {
  my $info = DBIx::Class::ResultSource->can('column_info');
  my $source = $schema->source('DevicePortVlan');
  local *DBIx::Class::ResultSource::column_info = sub {
    my ($self, $name) = @_;
    my $found = $info->(@_);
    return $name eq 'vlan' ? { %$found, data_type => 'integer); DROP TABLE device; --' } : $found;
  };
  remove_dies_like('DevicePortVlan', { ip => '192.0.2.1' }, [],
    qr/remove_unseen: column 'vlan' of 'device_port_vlan' has data type .* that cannot be used as a cast/, 'hostile type');
};

subtest 'remove_unseen__result_set_with_conditions__dies' => sub {
  my $device_ports = $schema->resultset('DevicePortVlan');
  foreach my $case (
    [ 'search' => $device_ports->search_rs({ port => ['Gi1'] }) ],
    [ 'me.ip search' => $device_ports->search_rs({ 'me.ip' => '192.0.2.1' }) ],
    [ 'relationship' => $schema->resultset('Device')->new_result({ ip => '192.0.2.1' })->related_resultset('port_vlans') ],
  ) {
    @ran = ();
    my ($name, $restricted) = @$case;
    ok(!eval { $restricted->remove_unseen({ ip => '192.0.2.1' }, []); 1 }, "$name: dies");
    like($@, qr/remove_unseen: this result set carries search conditions.*call remove_unseen on resultset\('DevicePortVlan'\)/, "$name: message");
    is(scalar @ran, 0, "$name: nothing sent");
  }
};

subtest 'remove_unseen__node_or_port_log_source__dies' => sub {
  remove_dies_like('Node', { mac => '00:11:22:33:44:55' }, [],
    qr/remove_unseen: 'Node' rows are never deleted by this method/, 'Node');
  remove_dies_like('DevicePortLog', { ip => '192.0.2.1' }, [],
    qr/remove_unseen: 'DevicePortLog' rows are never deleted by this method/, 'DevicePortLog');
};

subtest 'remove_unseen__scope_without_ip__dies' => sub {
  remove_dies_like('DeviceVlan', { vlan => 10 }, [],
    qr/remove_unseen: scope for 'device_vlan' must include 'ip'.*discover callers must scope by device/, 'DeviceVlan');
  remove_dies_like('DevicePortVlan', { port => 'Gi1' }, [ { vlan => 1, native => 0 } ],
    qr/remove_unseen: scope for 'device_port_vlan' must include 'ip'/, 'DevicePortVlan');
};

done_testing;
