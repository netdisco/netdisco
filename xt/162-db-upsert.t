#!/usr/bin/env perl

# upsert is a security boundary: later work sends discover's writes through
# it. Real result sources are used with a fake database handle, so these
# assert the SQL and binds sent. The behavior against PostgreSQL itself is
# checked outside netdisco CI.

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

sub upsert_ok {
  my ($source, $rows, $options) = @_;
  @ran = ();
  my $result = $schema->resultset($source)->upsert($rows, $options);
  return $result;
}

sub upsert_dies_like {
  my ($source, $rows, $regex, $name, $options) = @_;
  @ran = ();
  my $ok = eval { $schema->resultset($source)->upsert($rows, $options); 1 };
  my $error = $@;
  ok(!$ok, "$name: dies");
  like($error, $regex, "$name: message");
  is(scalar @ran, 0, "$name: nothing sent");
}

my $vlan = sub { +{ ip => '192.0.2.1', vlan => 10, description => 'a', @_ } };

subtest 'upsert__new_rows__one_insert_on_conflict_with_binds' => sub {
  upsert_ok('DeviceVlan', [ $vlan->() ]);
  is(scalar @ran, 1, 'one statement');
  is($ran[0][0], 'INSERT INTO "device_vlan" ("description", "ip", "vlan") VALUES (?, ?, ?)'
    . ' ON CONFLICT ("ip", "vlan") DO UPDATE SET "description" = EXCLUDED."description"'
    . ' WHERE ("device_vlan"."description") IS DISTINCT FROM (EXCLUDED."description")', 'sql');
  is_deeply([ @{$ran[0]}[1 .. 3] ], ['a', '192.0.2.1', 10], 'binds');
};

subtest 'upsert__insert_only_column__absent_from_set' => sub {
  upsert_ok('DeviceVlan', [ $vlan->(creation => 'x') ], { insert_only => ['creation'] });
  my $sql = $ran[0][0];
  like($sql, qr/\("creation", "description", "ip", "vlan"\) VALUES/, 'in the column list');
  unlike($sql, qr/SET.*creation/, 'not in SET or WHERE');
};

subtest 'upsert__touch_column__in_set_not_in_change_test' => sub {
  upsert_ok('DeviceVlan', [ $vlan->(last_discover => 'x') ], { touch => ['last_discover'] });
  my ($set, $where) = $ran[0][0] =~ /DO UPDATE SET (.*) WHERE (.*)\z/;
  like($set, qr/"last_discover" = EXCLUDED\."last_discover"/, 'in SET');
  unlike($where, qr/last_discover/, 'not in WHERE');
};

subtest 'upsert__only_touch_columns__do_nothing' => sub {
  upsert_ok('DeviceVlan', [ { ip => '192.0.2.1', vlan => 10, last_discover => 'x' } ],
    { touch => ['last_discover'] });
  like($ran[0][0], qr/ON CONFLICT \("ip", "vlan"\) DO NOTHING\z/, 'do nothing');
};

subtest 'upsert__timestamp_literals__inlined_not_bound' => sub {
  foreach my $literal (\'LOCALTIMESTAMP', \'to_timestamp(1761200000.123456)::timestamp',
                       \q{'2026-10-23 12:00:00.5'::timestamp}) {
    upsert_ok('DeviceVlan', [ $vlan->(last_discover => $literal) ]);
    my $text = $$literal;
    ok(index($ran[0][0], "VALUES (?, ?, $text, ?)") >= 0, "$text inlined in VALUES");
    is(scalar(@{$ran[0]}) - 1, 3, "$text adds no bind");
  }
};

subtest 'upsert__hostile_literal__dies' => sub {
  foreach my $literal (\'now(); DROP TABLE device', \q{to_timestamp(1)::timestamp; --},
                       \q{'x' || current_user::timestamp}, \['?', 1]) {
    upsert_dies_like('DeviceVlan', [ $vlan->(last_discover => $literal) ],
      qr/upsert: literal SQL .* not an allowed timestamp/, 'hostile literal');
  }
};

subtest 'upsert__unknown_or_hostile_column__dies' => sub {
  foreach my $name ('nope', 'vlan"; DROP TABLE device; --', 'description/**/') {
    upsert_dies_like('DeviceVlan', [ $vlan->($name => 1) ],
      qr/upsert: no column '.+' in table 'device_vlan'/, "column $name");
  }
};

subtest 'upsert__hostile_value__bound_verbatim' => sub {
  my $hostile = q{'); DROP TABLE device; --};
  upsert_ok('DeviceVlan', [ $vlan->(description => $hostile) ]);
  is($ran[0][1], $hostile, 'sent as a bind, unchanged');
  unlike($ran[0][0], qr/DROP TABLE/, 'absent from the SQL text');
};

subtest 'upsert__reserved_column_name__quoted' => sub {
  upsert_ok('DeviceModule', [ { ip => '192.0.2.1', index => 1, description => 'm' } ]);
  like($ran[0][0], qr/\("description", "index", "ip"\)/, 'column list quoted');
  like($ran[0][0], qr/ON CONFLICT \("ip", "index"\)/, 'conflict target quoted');
};

subtest 'upsert__array_value__bound_as_one' => sub {
  my $tags = ['a', 'b'];
  upsert_ok('DevicePort', [ { ip => '192.0.2.1', port => 'Gi1', tags => $tags } ]);
  is($ran[0][-1], $tags, 'array reference bound as one value');
  foreach my $bad ({ a => 1 }, sub {}) {
    upsert_dies_like('DevicePort', [ { ip => '192.0.2.1', port => 'Gi1', tags => $bad } ],
      qr/upsert: value for 'tags' .* must be/, 'non-array reference');
  }
  upsert_dies_like('DevicePort', [ { ip => '192.0.2.1', port => 'Gi1', tags => [ [1] ] } ],
    qr/upsert: value for 'tags' .* element that is itself a reference/, 'nested array');
};

subtest 'upsert__missing_or_undef_key__dies' => sub {
  upsert_dies_like('DeviceVlan', [ { ip => '192.0.2.1', description => 'a' } ],
    qr/upsert: .*key column 'vlan'/, 'missing key');
  upsert_dies_like('DeviceVlan', [ $vlan->(vlan => undef) ],
    qr/upsert: .*key column 'vlan'/, 'undef key');
};

subtest 'upsert__mixed_column_sets__dies' => sub {
  upsert_dies_like('DeviceVlan', [ $vlan->(), { ip => '192.0.2.1', vlan => 11 } ],
    qr/upsert: row 1 has columns .* row 0 has/, 'mixed columns');
};

subtest 'upsert__column_names_joined_like_a_list__dies' => sub {
  upsert_dies_like('DeviceVlan',
    [ { creation => 'x', description => 'y', ip => '192.0.2.1', vlan => 10 },
      { 'creation, description' => 'x', ip => '192.0.2.1', vlan => 11 } ],
    qr/upsert: row 1 has columns .* row 0 has/, 'joined column name');
};

subtest 'upsert__bad_arguments__die' => sub {
  upsert_dies_like('DeviceVlan', undef, qr/upsert: rows must be an array reference/, 'undef rows');
  upsert_dies_like('DeviceVlan', { ip => 1 }, qr/upsert: rows must be an array reference/, 'hash rows');
  upsert_dies_like('DeviceVlan', ['x'], qr/upsert: rows must be hash references/, 'non-hash row');
  upsert_dies_like('DeviceVlan', [ $vlan->() ], qr/upsert: unknown option 'insertonly'.*insert_only, touch/,
    'unknown option', { insertonly => ['creation'] });
  upsert_dies_like('DeviceVlan', [ $vlan->() ], qr/upsert: option 'touch' must be an array reference/,
    'scalar touch', { touch => 'last_discover' });
  upsert_dies_like('DeviceVlan', [ $vlan->() ], qr/upsert: option 'insert_only' must be an array reference/,
    'hash insert_only', { insert_only => {} });
  upsert_dies_like('DeviceVlan', [ $vlan->(last_discover => \undef) ],
    qr/upsert: literal SQL .* not an allowed timestamp/, 'reference to undef');
  upsert_dies_like('DeviceVlan', [ $vlan->(vlan => [10]) ], qr/upsert: .*key column 'vlan'/, 'reference key');
  upsert_dies_like('DeviceVlan', [ $vlan->(), $vlan->(vlan => 11, last_discover => \'x') ],
    qr/upsert: row 1 has columns/, 'later row with extra column');
  upsert_dies_like('DeviceVlan',
    [ $vlan->(last_discover => \'LOCALTIMESTAMP'), $vlan->(vlan => 11, last_discover => \'now(); DROP TABLE device') ],
    qr/upsert: literal SQL .* not an allowed timestamp/, 'hostile literal in a later row');
};

subtest 'upsert__duplicate_key__dies' => sub {
  upsert_dies_like('DeviceVlan', [ $vlan->(), $vlan->() ],
    qr/upsert: duplicate key \(192\.0\.2\.1, 10\) in rows for 'device_vlan'; the caller must pass each key once/,
    'duplicate key');
};

subtest 'upsert__no_rows__sends_nothing' => sub {
  is(upsert_ok('DeviceVlan', []), 0, 'returns 0');
  is(scalar @ran, 0, 'nothing sent');
};

subtest 'upsert__many_rows__batched_by_bind_limit_in_key_order' => sub {
  my @rows = map { { ip => '192.0.2.1', vlan => $_, description => 'a' } } reverse 1 .. 30000;
  @counts = (21845, 8155);
  my $total = upsert_ok('DeviceVlan', \@rows);
  is(scalar @ran, 2, 'two statements');
  is($total, 30000, 'sum of the counts');
  is(scalar(@{$ran[0]}) - 1, 21845 * 3, 'first statement is full');
  is_deeply([ @{$ran[0]}[1 .. 3] ], ['a', '192.0.2.1', 1], 'first row is the lowest key');
  is(scalar(@{$ran[1]}) - 1, 8155 * 3, 'rest in the second');
};

done_testing;
