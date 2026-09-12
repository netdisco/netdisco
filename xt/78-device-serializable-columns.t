#!/usr/bin/env perl

# Every API route that serializes a device row builds it from TO_JSON, which
# takes its field list from serializable_columns, so the stored SNMP read
# community is dropped there rather than at each route.
#
# No database is needed: a result source answers ->columns, and a row built
# with new_result serializes without ever being stored.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco::DB;

my $schema = do {
    local $SIG{__WARN__} = sub { };
    App::Netdisco::DB->connect('dbi:Pg:dbname=netdisco_xt_78_absent');
};

my $SECRET = 'snmp_comm';

sub device_rs { return $schema->resultset('Device') }

subtest 'deviceResult__the_column_this_guard_protects__is_still_in_the_schema' => sub {
    my %columns = map { $_ => 1 } device_rs()->result_source->columns;

    ok( $columns{$SECRET},
      "$SECRET is a Device column, so dropping it from the list means something" );
};

subtest 'deviceResult__serializableColumns__omits_the_community' => sub {
    my $row = device_rs()->new_result({});
    my %serializable = map { $_ => 1 } @{ $row->serializable_columns };

    ok( ! $serializable{$SECRET}, "$SECRET is not serializable" );
};

subtest 'deviceResult__serializableColumns__keeps_every_other_column' => sub {
    my $row = device_rs()->new_result({});
    my %serializable = map { $_ => 1 } @{ $row->serializable_columns };

    # the helper already drops columns by data type, so its own test for that
    # says which absences are expected and this one does not have to list them
    my @missing = grep { $_ ne $SECRET
                         and $row->_is_column_serializable($_)
                         and ! $serializable{$_} }
                       device_rs()->result_source->columns;

    is( "@missing", q{}, 'no ordinary column was dropped alongside it' );
};

subtest 'deviceResult__toJson__does_not_carry_the_community' => sub {
    my $row = device_rs()->new_result({
      ip => '192.0.2.1', dns => 'device.example', $SECRET => 'a-secret',
    });
    my $data = $row->TO_JSON;

    ok( ! exists $data->{$SECRET}, 'the serialized row has no such key' );
    is( $data->{'dns'}, 'device.example', 'and still carries its ordinary fields' );
};

subtest 'otherResult__serializableColumns__is_not_narrowed' => sub {
    my $row = $schema->resultset('DevicePort')->new_result({});
    my %serializable = map { $_ => 1 } @{ $row->serializable_columns };

    my @missing = grep { ! $serializable{$_} }
                       $schema->resultset('DevicePort')->result_source->columns;

    is( "@missing", q{}, 'a result class with no credential keeps every column' );
};

done_testing();
