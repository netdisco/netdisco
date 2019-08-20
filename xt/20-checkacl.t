#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 1.302083;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

BEGIN {
  use_ok( 'App::Netdisco::Configuration', 'check_acl' );
  use_ok( 'App::Netdisco::Util::Permission', 'check_acl' );
}

use Dancer qw/:script !pass/;

my @conf = (
  # +ve match       -ve match
  'localhost',     '!www.example.com', # 0, 1
  '127.0.0.1',     '!192.0.2.1',       # 2, 3
  '::1',           '!2001:db8::1',     # 4, 5
  '127.0.0.0/29',  '!192.0.2.0/24',    # 6, 7
  '::1/128',       '!2001:db8::/32',   # 8, 9

  '127.0.0.1-10',  '!192.0.2.1-10',    # 10,11
  '::1-10',        '!2001:db8::1-10',  # 12,13

  qr/^localhost$/, qr/^www.example.com$/,    # 14,15
  qr/(?!:www.example.com)/, '!127.0.0.0/29', # 16,17
  '!127.0.0.1-10', qr/(?!:localhost)/,       # 18,19

  'op:and',    # 20
  'group:groupreftest',  # 21
  '!group:groupreftest', # 22
);

# name, ipv4, ipv6, v4 prefix, v6 prefix
ok(check_acl('localhost',[$conf[0]]), 'same name');
ok(check_acl('127.0.0.1',[$conf[2]]), 'same ipv4');
ok(check_acl('::1',[$conf[4]]), 'same ipv6');
ok(check_acl('127.0.0.0/29',[$conf[6]]), 'same v4 prefix');
ok(check_acl('::1/128',[$conf[8]]), 'same v6 prefix');

# failed name, ipv4, ipv6, v4 prefix, v6 prefix
is(check_acl('www.microsoft.com',[$conf[0]]),  0, 'failed name');
is(check_acl('172.20.0.1',[$conf[2]]),         0, 'failed ipv4');
is(check_acl('2001:db8::5',[$conf[4]]),        0, 'failed ipv6');
is(check_acl('172.16.1.3/29',[$conf[6]]),      0, 'failed v4 prefix');
is(check_acl('2001:db8:f00d::/64',[$conf[8]]), 0, 'failed v6 prefix');

# negated name, ipv4, ipv6, v4 prefix, v6 prefix
ok(check_acl('localhost',[$conf[1]]), 'not same name');
ok(check_acl('127.0.0.1',[$conf[3]]), 'not same ipv4');
ok(check_acl('::1',[$conf[5]]), 'not same ipv6');
ok(check_acl('127.0.0.0/29',[$conf[7]]), 'not same v4 prefix');
ok(check_acl('::1/128',[$conf[9]]), 'not same v6 prefix');

# v4 range, v6 range
ok(check_acl('127.0.0.1',[$conf[10]]), 'in v4 range');
ok(check_acl('::1',[$conf[12]]), 'in v6 range');

# failed v4 range, v6 range
is(check_acl('172.20.0.1',[$conf[10]]), 0, 'failed v4 range');
is(check_acl('2001:db8::5',[$conf[12]]), 0, 'failed v6 range');

# negated v4 range, v6 range
ok(check_acl('127.0.0.1',[$conf[11]]), 'not in v4 range');
ok(check_acl('::1',[$conf[13]]), 'not in v6 range');

# hostname regexp
# FIXME ok(check_acl('localhost',[$conf[14]]), 'name regexp');
# FIXME ok(check_acl('127.0.0.1',[$conf[14]]), 'IP regexp');
is(check_acl('www.google.com',[$conf[14]]), 0, 'failed regexp');

# OR of prefix, range, regexp, property (2 of, 3 of, 4 of)
ok(check_acl('127.0.0.1',[@conf[8,0]]), 'OR: prefix, name');
ok(check_acl('127.0.0.1',[@conf[8,12,0]]), 'OR: prefix, range, name');
ok(check_acl('127.0.0.1',[@conf[8,12,15,0]]), 'OR: prefix, range, regexp, name');

# OR of negated prefix, range, regexp, property (2 of, 3 of, 4 of)
ok(check_acl('127.0.0.1',[@conf[17,0]]), 'OR: !prefix, name');
ok(check_acl('127.0.0.1',[@conf[17,18,0]]), 'OR: !prefix, !range, name');
ok(check_acl('127.0.0.1',[@conf[17,18,19,0]]), 'OR: !prefix, !range, !regexp, name');

# AND of prefix, range, regexp, property (2 of, 3 of, 4 of)
ok(check_acl('127.0.0.1',[@conf[6,0,20]]), 'AND: prefix, name');
ok(check_acl('127.0.0.1',[@conf[6,10,0,20]]), 'AND: prefix, range, name');
# FIXME ok(check_acl('127.0.0.1',[@conf[6,10,14,0,20]]), 'AND: prefix, range, regexp, name');

# failed AND on prefix, range, regexp
is(check_acl('127.0.0.1',[@conf[8,10,14,0,20]]), 0, 'failed AND: prefix!, range, regexp, name');
is(check_acl('127.0.0.1',[@conf[6,12,14,0,20]]), 0, 'failed AND: prefix, range!, regexp, name');
is(check_acl('127.0.0.1',[@conf[6,10,15,0,20]]), 0, 'failed AND: prefix, range, regexp!, name');

# AND of negated prefix, range, regexp, property (2 of, 3 of, 4 of)
ok(check_acl('127.0.0.1',[@conf[9,0,20]]), 'AND: !prefix, name');
ok(check_acl('127.0.0.1',[@conf[7,11,0,20]]), 'AND: !prefix, !range, name');
ok(check_acl('127.0.0.1',[@conf[9,13,16,0,20]]), 'AND: !prefix, !range, !regexp, name');

# group ref
is(check_acl('192.0.2.1',[$conf[22]]), 1, '!missing group ref');
is(check_acl('192.0.2.1',[$conf[21]]), 0, 'failed missing group ref');
setting('host_groups')->{'groupreftest'} = ['192.0.2.1'];
is(check_acl('192.0.2.1',[$conf[21]]), 1, 'group ref');
is(check_acl('192.0.2.1',[$conf[22]]), 0, 'failed !missing group ref');

# scalar promoted to list
ok(check_acl('localhost',$conf[0]), 'scalar promoted');
ok(check_acl('localhost',$conf[1]), 'not scalar promoted');
is(check_acl('www.microsoft.com',$conf[0]),  0, 'failed scalar promoted');

# device property
# negated device property

done_testing;
