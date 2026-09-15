#!/usr/bin/env perl

# The DataTables columns[i][data] parameter arrives from the request and both
# the filtering and the ordering clause use it as an SQL identifier, so a name
# must be one the resultset resolves.
#
# Both clauses are driven here because they reach that parameter by different
# routes: the ordering case needs an empty search[value], the state that
# leaves the filtering loop unentered, and the filtering case puts the name on
# a column the ordering clause never looks at. A guard on one clause alone
# passes half of this file.
#
# No database is needed: the assertions read the SQL that DBIC would send.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco::DB;

# the versioned schema reaches for the database as it connects and warns when
# it cannot find one
my $schema = do {
    local $SIG{__WARN__} = sub { };
    App::Netdisco::DB->connect('dbi:Pg:dbname=netdisco_xt_74_absent');
};

# a name the resultset does not resolve, in both the shapes the caller can
# send: a bare word, which is the only form the table-alias prefix rewrites,
# and one that is not a word at all
my @UNRESOLVED = ( 'not_a_column', '(1)' );

sub params_for {
    my %arg     = @_;
    my $columns = {};
    my $index   = 0;

    foreach my $name ( @{ $arg{'columns'} } ) {
        $columns->{ $index++ } = { data => $name, searchable => 'true' };
    }

    return {
        columns => $columns,
        order   => { 0 => { column => ( $arg{'order_column'} || 0 ),
                            dir    => 'asc' } },
        search  => { value => ( defined $arg{'search'} ? $arg{'search'} : q{} ) },
        length  => 10,
        start   => 0,
    };
}

sub sql_for {
    my ( $rs, $params ) = @_;
    return ${ $rs->get_datatables_data($params)->as_query }->[0];
}

sub userlog_rs { return $schema->resultset('UserLog') }

# the shape the Node Vendor Inventory report builds, which reaches columns of
# two joined tables and none of the other columns of either.
# assigned before returning because search in list context runs the query
sub nodevendor_rs {
    my $rs = $schema->resultset('Node')->search(
        undef,
        {   '+columns' => [
                qw/ device.dns device.name manufacturer.abbrev manufacturer.company /
            ],
            join     => [qw/ manufacturer device /],
            collapse => 1,
        }
    );
    return $rs;
}

subtest 'get_datatables_data__ordering_column_is_not_resolved__dies' => sub {
    foreach my $name (@UNRESOLVED) {
        my $sql = eval {
            sql_for( userlog_rs(),
                params_for( columns => [$name], search => q{} ) );
        };
        my $error = $@;

        is( $sql, undef, 'no query is built' );
        like( $error, qr/unknown DataTables column/,
            'the ordering clause refuses a name it did not resolve' );
    }
};

subtest 'get_datatables_data__filtering_column_is_not_resolved__dies' => sub {
    foreach my $name (@UNRESOLVED) {
        my $sql = eval {
            sql_for(
                userlog_rs(),
                params_for(
                    columns      => [ 'username', $name ],
                    search       => 'anything',
                    order_column => 0,
                )
            );
        };
        my $error = $@;

        is( $sql, undef, 'no query is built' );
        like( $error, qr/unknown DataTables column/,
            'the filtering clause refuses a name it did not resolve' );
    }
};

subtest 'get_datatables_filtered_count__filtering_column_is_not_resolved__dies' => sub {
    foreach my $name (@UNRESOLVED) {
        my $count = eval {
            userlog_rs()->get_datatables_filtered_count(
                params_for(
                    columns      => [ 'username', $name ],
                    search       => 'anything',
                    order_column => 0,
                )
            );
        };
        my $error = $@;

        is( $count, undef, 'no count is returned' );
        like( $error, qr/unknown DataTables column/,
            'the second entry point to the filtering clause is guarded too' );
    }
};

subtest 'get_datatables_data__resolved_column__reaches_both_clauses' => sub {
    my $sql = sql_for( userlog_rs(),
        params_for( columns => ['username'], search => 'admin' ) );

    like( $sql, qr/ORDER BY me[.]username ASC/, 'orders on the column' );
    like( $sql, qr/me[.]username::text LIKE [?]/, 'filters on the column' );
};

subtest 'get_datatables_data__joined_column__reaches_both_clauses' => sub {
    my $sql = sql_for( nodevendor_rs(),
        params_for( columns => ['manufacturer.abbrev'], search => 'cisco' ) );

    like( $sql, qr/ORDER BY manufacturer[.]abbrev ASC/,
        'orders on the joined column' );
    like( $sql, qr/manufacturer[.]abbrev::text LIKE [?]/,
        'filters on the joined column' );
};

subtest 'get_datatables_data__column_the_resultset_does_not_select__dies' => sub {
    my $sql = eval {
        sql_for( nodevendor_rs(),
            params_for( columns => ['device.model'], search => q{} ) );
    };
    my $error = $@;

    is( $sql, undef, 'no query is built' );
    like( $error, qr/manufacturer[.]abbrev/,
        'a joined column the report does select is offered' );
    unlike( $error, qr/model/,
        'a column of the same joined table that it does not select is absent' );
};

subtest 'get_datatables_data__virtual_result_source__reaches_both_clauses' => sub {
    my $sql = sql_for( $schema->resultset('Virtual::ApRadioChannelPower'),
        params_for( columns => ['port_name'], search => 'wlan' ) );

    like( $sql, qr/ORDER BY me[.]port_name ASC/,
        'orders on a column of the virtual view' );
    like( $sql, qr/me[.]port_name::text LIKE [?]/,
        'filters on a column of the virtual view' );
};

subtest 'get_datatables_data__refused_column__error_omits_the_request_value' => sub {
    eval {
        sql_for( userlog_rs(),
            params_for( columns => [ $UNRESOLVED[0] ], search => q{} ) );
    };
    my $error = $@;

    unlike( $error, qr/\Q$UNRESOLVED[0]\E/,
        'the refusal does not echo the value it was sent' );
    like( $error, qr/expected one of: entry, username/,
        'it names the columns the resultset does resolve' );
};

# The guard makes an unresolvable name fatal, so a column a shipped report
# sends that its own resultset does not select would take that page down. Each
# resultset below is built in the shape its route builds, and the names come
# from the template rather than a copy of them, so a column added to one and
# not to the other is caught here.

sub server_side_columns {
    my $template = shift;
    open my $fh, '<', $template or die "$template: $!";
    my $body = do { local $/; <$fh> };

    # the two tables in a report are the branches of one IF, so the
    # server-side column list ends where the client-side branch begins
    $body =~ s/.*?"serverSide":\s*true//s or return ();
    $body =~ s/\[%\s*ELSE\s*%\].*//s;

    # the column lists are JSON but were single-quoted before the
    # interface was rebuilt, so both spellings are read
    return ( $body =~ /"data":\s*["']([^"']+)["']/g );
}

subtest 'get_datatables_data__every_column_a_shipped_report_sends__resolves' => sub {
    my %report = (
        'ajax/admintask/userlog.tt' => sub { userlog_rs() },
        'ajax/report/nodevendor.tt' => sub { nodevendor_rs() },
        'ajax/report/apradiochannelpower.tt' =>
            sub { $schema->resultset('Virtual::ApRadioChannelPower') },
        'ajax/report/devicepoestatus.tt' =>
            sub { $schema->resultset('Virtual::DevicePoeStatus') },
        'ajax/report/netbios.tt' => sub {
            $schema->resultset('NodeNbt')->search( { domain => q{} } )
                ->order_by( [ { -asc => 'domain' }, { -desc => 'time_last' } ] );
        },
        'ajax/report/moduleinventory.tt' => sub {
            $schema->resultset('DeviceModule')->columns(
                [   'ip',     'description', 'name',   'class',
                    'type',   'serial',      'hw_ver', 'fw_ver',
                    'sw_ver', 'model'
                ]
                )->search(
                {},
                {   '+columns' => [qw/ device.dns device.name /],
                    join       => 'device',
                    collapse   => 1,
                }
                );
        },
    );

    foreach my $template ( sort keys %report ) {
        my @columns = server_side_columns("share/views/$template");
        ok( scalar @columns, "$template names its server-side columns" );

        my %resolved = map { $_ => 1 }
            @{ $report{$template}->()->_resolved_attrs->{'as'} || [] };
        my @refused = grep { !$resolved{$_} } @columns;

        is( "@refused", q{}, "$template sends only columns its report selects" );
    }
};

done_testing();
