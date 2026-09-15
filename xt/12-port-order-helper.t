#!/usr/bin/env perl

# Coverage for App::Netdisco::DB::ResultSet::DevicePort::order_by_port_name,
# the helper schema 99 exists to serve. xt/11-port-sortkey.t proves the
# port_sortkey() function reproduces portsort.js's order; this file proves the
# helper puts that function into an ORDER BY with the right terms in the right
# places, which is a separate claim and the one the Ports tab depends on.
#
# The assertions are on the SQL the resultset emits, not on rows fetched back.
# That is deliberate: the order the rows arrive in is a property of
# port_sortkey(), already covered next door over all 125 corpus names, while
# what can silently regress here is the term order and the merge behaviour.
#
# Note there is no DANCER_ENVDIR=/dev/null here, unlike most of its neighbours.
# That setting empties the DSN, and this file needs a real one.

use strict;
use warnings;

use Test::More 0.88;

# Dancer's DSL is imported into its own package rather than into main, because
# it exports a `pass` that collides with Test::More's and Perl warns about the
# prototype mismatch.
{
    package NetdiscoSchema;
    use App::Netdisco;
    use Dancer qw/:moose :script/;
    use Dancer::Plugin::DBIC 'schema';
    sub connected { my $s = schema('netdisco'); $s->storage->dbh_do(sub { $_[1]->do('SELECT 1') }); return $s }
}

my $schema = eval { NetdiscoSchema::connected() };
my $why = $@;

SKIP: {
    skip "no usable netdisco database: $why", 6 if not $schema;

    my $rs = $schema->resultset('DevicePort');

    # Everything below runs against a scratch schema rather than public, so a
    # developer running this against a real database is not left with a function
    # they did not deploy.
    my $scratch = "nd_order_test_$$";
    my $dbh = $schema->storage->dbh;
    $dbh->do("CREATE SCHEMA $scratch");
    $main::SCRATCH = { dbh => $dbh, name => $scratch };

    # public is deliberately OFF the search_path for the two guard assertions
    # below. _assert_port_sortkey resolves to_regprocedure('port_sortkey(text)')
    # through the search_path, so on a database where schema 99 is already
    # deployed the guard would succeed and those two tests would fail for the
    # rest of time. Hiding public forces the missing-function case on every
    # database instead of only on one that has not upgraded yet.
    $dbh->do("SET search_path = $scratch");

    # The guard also has to be tested before anything satisfies it: it memoizes
    # into a file scoped lexical the moment it succeeds, so a later call cannot
    # see the missing-function case again in this process.
    my $missing = eval { $rs->order_by_port_name([]); 1 };
    my $complaint = $@;
    ok(! $missing, 'the helper refuses to build a query when port_sortkey() is absent');
    like($complaint, qr/netdisco-db-deploy/,
        'and the complaint names the command that installs it');

    open my $fh, '<', 'share/schema_versions/App-Netdisco-DB-98-99-PostgreSQL.sql'
        or die "migration: $!";
    my $migration = do { local $/; <$fh> };
    close $fh;
    $dbh->do($migration);

    my $sql_of = sub {
        my $set = shift;
        my ($sql) = @{ ${ $set->as_query } };
        $sql =~ s/\s+/ /g;
        return $sql;
    };

    my $plain = $sql_of->( $rs->order_by_port_name([]) );

    like($plain, qr/ORDER BY port_sortkey\(me\.port\) COLLATE "C", me\.port COLLATE "C"/,
        'the port key leads and the raw port name breaks its ties');

    # port_sortkey() deliberately ties equivalent names, 10GigabitEthernet1/1
    # against GigabitEthernet1/1, so without the tiebreak the order within a tie
    # is whatever Postgres returns, which is what would make paging unsafe.
    my ($keypos) = $plain =~ /ORDER BY (.*)$/;
    my @terms = split /,\s*/, $keypos;
    is(scalar @terms, 2, 'and nothing else is ordering by default');

    # The Ports tab passes node ordering here rather than chaining a second
    # order_by, because a chained one replaces rather than appends. With a
    # prefetched has_many DBIC collapses rows into objects and needs each port's
    # rows contiguous, so a node column sorted ahead of the port name would
    # break the collapse.
    my $with_nodes = $sql_of->( $rs->order_by_port_name([
        \'regexp_replace(COALESCE(active_nodes.vlan, \'0\'), \'[^0-9]*\', \'0\') :: integer',
        'active_nodes.mac',
    ]) );

    like($with_nodes, qr/ORDER BY port_sortkey\(me\.port\) COLLATE "C", me\.port COLLATE "C", regexp_replace/,
        'extra terms are appended after the port key, never ahead of it');

    # search_rs, not search: search is context sensitive and would hand the
    # helper's rows to $sql_of instead of the resultset.
    my $chained = $sql_of->( $rs->order_by_port_name([])->search_rs({}, { order_by => 'me.mac' }) );
    unlike($chained, qr/port_sortkey/,
        'a chained order_by really does discard the port key, which is why the helper takes the extra terms');
}

END {
    if ($main::SCRATCH) {
        eval { $main::SCRATCH->{dbh}->do("SET search_path = public") };
        eval { $main::SCRATCH->{dbh}->do("DROP SCHEMA $main::SCRATCH->{name} CASCADE") };
    }
}

done_testing;
