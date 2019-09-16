#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 1.302083;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

BEGIN {
  use_ok( 'App::Netdisco::Configuration' );
  use_ok( 'App::Netdisco::Util::Permission', 'acl_to_where_clause' );
}

use SQL::Abstract;
use Dancer qw/:script !pass/;

config->{'host_groups'} = {
  include1 => [
    'op:and',
    'model:.*(?i:DCS7508).*',
    qr/^.*\.backbone\.example\.com$/
  ],
  include2 => 'model:\w+6500\w*',
  primary => [
    'www.google.com',
    '192.0.2.1',
    '2001:db8::/32',
    '192.0.2.1-10',
    '!192.0.2.20-30',
    qr/^sep0.*$/,
    'vendor:cisco',
    'group:include1',
    'group:include2',
    '!192.0.2.0/29',
    'any',
    '!any',
  ],
};

my $clause = acl_to_where_clause(setting('host_groups')->{'primary'});
my $sqla = SQL::Abstract->new();

my $compiled = ' WHERE ( ('
.' ip <<= ?'
.' OR ip <<= ?'
.' OR ip <<= ?'
.' OR ( ip >= ? AND ip <= ? )'
.' OR ( ip < ? OR ip > ? )'
.' OR ( dns IS NOT NULL AND match(dns, ?) )'
.' OR ( vendor IS NOT NULL AND match(vendor, ?) )'
.' OR ( ( model IS NOT NULL AND match(model, ?) ) AND ( dns IS NOT NULL AND match(dns, ?) ) )'
.' OR ( model IS NOT NULL AND match(model, ?) )'
.' OR (NOT ip <<= ?)'
.' OR ( ip <<= ? OR ip <<= ? )'
.' OR ( ip <<= ? AND ip <<= ? )'
.' ) )';

is($sqla->where($clause), $compiled, 'syntax in compiled WHERE clause');

done_testing;
