#!/usr/bin/env perl

# The Ports tab's order comes from share/public/javascripts/portsort.js, and
# schema 99 adds port_sortkey() so Postgres can produce the same order in an
# ORDER BY. This file is the check that it does, measured against the corpus
# xt/js/portsort.test.js and xt/10-sort_port.t share.
#
# Note there is no DANCER_ENVDIR=/dev/null here, unlike its neighbours. That
# setting empties the DSN, and this file needs a real one.

use strict;
use warnings;

use Test::More 0.88;
use JSON::PP 'decode_json';

my $MIGRATION = 'share/schema_versions/App-Netdisco-DB-98-99-PostgreSQL.sql';

# Read the file the way DBIx::Class::Schema::Versioned::_read_sql_file does,
# rather than reading it as SQL: drop comment and transaction lines, join the
# rest with NO separator, split on ";". Everything this reproduces is a rule the
# migration has to satisfy, and each one fails silently at deploy time, because
# App::Netdisco::DB::SchemaVersioned catches the error and stamps the version
# anyway. Asserting the split here is the only place a violation is loud.
sub statements_as_deployed {
    open my $fh, '<', $MIGRATION or die "$MIGRATION: $!";
    my @lines = split /\n/, join '', <$fh>;
    close $fh;
    @lines = grep { $_ && $_ !~ /^--/ && $_ !~ /^(BEGIN|BEGIN TRANSACTION|COMMIT)/m } @lines;
    return grep { /\S/ } split /;/, join '', @lines;
}

my @statements = statements_as_deployed();

is(scalar @statements, 1, 'the migration survives the upgrade reader as one statement')
    or diag("got $#{[@statements]} + 1 fragments; a semicolon inside the \$\$ body splits them");

like($statements[0], qr/CREATE OR REPLACE FUNCTION\s+port_sortkey\(raw text\)/,
    'that statement is the port_sortkey definition');

# An unindented continuation line fuses its first token to the previous line's
# last one once the newlines are gone. The result is still one statement, so the
# count above cannot catch it, and Postgres reports it only at deploy time.
unlike($statements[0], qr/\)RETURNS|textLANGUAGE|\$\$WITH/,
    'no two lines fused together for want of leading whitespace');

my $corpus = decode_json(do {
    open my $fh, '<:raw', 'xt/portsort-corpus.json'
        or die "xt/portsort-corpus.json: $!";
    local $/; <$fh>;
});

# From here on a database is needed. Skipping is reported with the reason
# printed, never silently: a skip that hides a broken connection would leave
# this file green while proving nothing.
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
    skip "no usable netdisco database: $why", 2 if not $schema;

    # Installed into a scratch schema rather than into public, so a developer
    # running this against a real database is not left with a function they did
    # not deploy. Dropped in the END block below whatever happens next.
    my $scratch = "nd_sortkey_test_$$";
    my $dbh = $schema->storage->dbh;
    $dbh->do("CREATE SCHEMA $scratch");
    $main::SCRATCH = { dbh => $dbh, name => $scratch };
    $dbh->do("SET search_path = $scratch");
    $dbh->do($statements[0]);

    my ($installed) = $dbh->selectrow_array(
        "SELECT to_regprocedure('$scratch.port_sortkey(text)') IS NOT NULL");
    ok($installed, 'the statement installs as a callable port_sortkey(text)');

    my $values = join ',', map { '(' . $dbh->quote($_) . ')' } @{ $corpus->{names} };
    my $ordered = $dbh->selectcol_arrayref(
        qq{SELECT p FROM (VALUES $values) AS t(p)
             ORDER BY port_sortkey(p) COLLATE "C", p COLLATE "C"});

    is_deeply($ordered, $corpus->{order},
        'the SQL order matches the order portsort.js produces')
        or diag('first difference at position '
            . (grep { $ordered->[$_] ne $corpus->{order}[$_] } 0 .. $#{ $corpus->{order} })[0]);
}

END {
    if ($main::SCRATCH) {
        eval { $main::SCRATCH->{dbh}->do("DROP SCHEMA $main::SCRATCH->{name} CASCADE") };
    }
}

done_testing;
