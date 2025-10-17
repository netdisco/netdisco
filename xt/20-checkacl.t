#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 1.302083;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

BEGIN {
  use_ok( 'App::Netdisco::Configuration' );
  use_ok( 'App::Netdisco::Util::Permission', 'acl_matches' );
}

use Dancer qw/:script !pass/;

my @conf = (
  # +ve match       -ve match
  'localhost',     '!www.example.com', # 0, 1
  '127.0.0.1',     '!192.0.2.1',       # 2, 3
  '::1',           '!2001:db8::1',     # 4, 5
  '127.0.0.0/29',  '!192.0.2.0/24',    # 6, 7
  '::1/128',       '!2001:db8::/32',   # 8, 9

  '127.0.0.1-10',  '!192.0.2.1-10',    # 10,11
  '::1-10',        '!2001:db8::1-10',  # 12,13

  qr/^localhost$/, qr/^www.example.com$/,    # 14,15
  qr/(?!:www.example.com)/, '!127.0.0.0/29', # 16,17
  '!127.0.0.1-10', qr/(?!:localhost)/,       # 18,19

  'op:and',    # 20
  'group:groupreftest',  # 21
  '!group:groupreftest', # 22

  '192.0.2.1', #23

  '1 1 1 1 1', #24
  '* * * * *', #25
  '1 1 1 1 1 *', #26
  '* * * * * *', #27
  '!1 1 1 1 1', #28
  '!* * * * *', #29

  '!port:TwentyFiveGigE\d\/\d\/\d+', #30
  '!port:TenGigabitEthernet\d\/\d+', #31 
);

# name, ipv4, ipv6, v4 prefix, v6 prefix
ok(acl_matches('localhost',[$conf[0]]), 'same name');
ok(acl_matches('127.0.0.1',[$conf[2]]), 'same ipv4');
ok(acl_matches('::1',[$conf[4]]), 'same ipv6');
ok(acl_matches('127.0.0.0/29',[$conf[6]]), 'same v4 prefix');
ok(acl_matches('::1/128',[$conf[8]]), 'same v6 prefix');

# failed name, ipv4, ipv6, v4 prefix, v6 prefix
is(acl_matches('www.microsoft.com',[$conf[0]]),  0, 'failed name');
is(acl_matches('172.20.0.1',[$conf[2]]),         0, 'failed ipv4');
is(acl_matches('2001:db8::5',[$conf[4]]),        0, 'failed ipv6');
is(acl_matches('172.16.1.3/29',[$conf[6]]),      0, 'failed v4 prefix');
is(acl_matches('2001:db8:f00d::/64',[$conf[8]]), 0, 'failed v6 prefix');

# negated name, ipv4, ipv6, v4 prefix, v6 prefix
ok(acl_matches('localhost',[$conf[1]]), 'not same name');
ok(acl_matches('127.0.0.1',[$conf[3]]), 'not same ipv4');
ok(acl_matches('::1',[$conf[5]]), 'not same ipv6');
ok(acl_matches('127.0.0.0/29',[$conf[7]]), 'not same v4 prefix');
ok(acl_matches('::1/128',[$conf[9]]), 'not same v6 prefix');

# v4 range, v6 range
ok(acl_matches('127.0.0.1',[$conf[10]]), 'in v4 range');
ok(acl_matches('::1',[$conf[12]]), 'in v6 range');

# failed v4 range, v6 range
is(acl_matches('172.20.0.1',[$conf[10]]), 0, 'failed v4 range');
is(acl_matches('2001:db8::5',[$conf[12]]), 0, 'failed v6 range');

# negated v4 range, v6 range
ok(acl_matches('127.0.0.1',[$conf[11]]), 'not in v4 range');
ok(acl_matches('::1',[$conf[13]]), 'not in v6 range');

# hostname regexp
# FIXME ok(acl_matches('localhost',[$conf[14]]), 'name regexp');
# FIXME ok(acl_matches('127.0.0.1',[$conf[14]]), 'IP regexp');
is(acl_matches('www.google.com',[$conf[14]]), 0, 'failed regexp');

# OR of prefix, range, regexp, property (2 of, 3 of, 4 of)
ok(acl_matches('127.0.0.1',[@conf[8,0]]), 'OR: prefix, name');
ok(acl_matches('127.0.0.1',[@conf[8,12,0]]), 'OR: prefix, range, name');
ok(acl_matches('127.0.0.1',[@conf[8,12,15,0]]), 'OR: prefix, range, regexp, name');

# OR of negated prefix, range, regexp, property (2 of, 3 of, 4 of)
ok(acl_matches('127.0.0.1',[@conf[17,0]]), 'OR: !prefix, name');
ok(acl_matches('127.0.0.1',[@conf[17,18,0]]), 'OR: !prefix, !range, name');
ok(acl_matches('127.0.0.1',[@conf[17,18,19,0]]), 'OR: !prefix, !range, !regexp, name');

# AND of prefix, range, regexp, property (2 of, 3 of, 4 of)
ok(acl_matches('127.0.0.1',[@conf[6,0,20]]), 'AND: prefix, name');
ok(acl_matches('127.0.0.1',[@conf[6,10,0,20]]), 'AND: prefix, range, name');
# FIXME ok(acl_matches('127.0.0.1',[@conf[6,10,14,0,20]]), 'AND: prefix, range, regexp, name');

# failed AND on prefix, range, regexp
is(acl_matches('127.0.0.1',[@conf[8,10,14,0,20]]), 0, 'failed AND: prefix!, range, regexp, name');
is(acl_matches('127.0.0.1',[@conf[6,12,14,0,20]]), 0, 'failed AND: prefix, range!, regexp, name');
is(acl_matches('127.0.0.1',[@conf[6,10,15,0,20]]), 0, 'failed AND: prefix, range, regexp!, name');

# AND of negated prefix, range, regexp, property (2 of, 3 of, 4 of)
ok(acl_matches('127.0.0.1',[@conf[9,0,20]]), 'AND: !prefix, name');
ok(acl_matches('127.0.0.1',[@conf[7,11,0,20]]), 'AND: !prefix, !range, name');
ok(acl_matches('127.0.0.1',[@conf[9,13,16,0,20]]), 'AND: !prefix, !range, !regexp, name');

# group ref
is(acl_matches('192.0.2.1',[$conf[22]]), 1, '!missing group ref');
is(acl_matches('192.0.2.1',[$conf[21]]), 0, 'failed missing group ref');
setting('host_groups')->{'groupreftest'} = ['192.0.2.1'];
is(acl_matches('192.0.2.1',[$conf[21]]), 1, 'group ref');
is(acl_matches('192.0.2.1',[$conf[22]]), 0, 'failed !missing group ref');

# scalar promoted to list
ok(acl_matches('localhost',$conf[0]), 'scalar promoted');
ok(acl_matches('localhost',$conf[1]), 'not scalar promoted');
is(acl_matches('www.microsoft.com',$conf[0]),  0, 'failed scalar promoted');

use App::Netdisco::DB;
my $dip = App::Netdisco::DB->resultset('DeviceIp')->new_result({
   ip   => '127.0.0.1',
   port => 'TenGigabitEthernet1/10',
   alias => '192.0.2.1',
   device_port =>
     App::Netdisco::DB->resultset('DevicePort')->new_result({
          ip   => '127.0.0.1',
          port => 'TenGigabitEthernet1/10',
          type => 'l3ipvlan',
      })
});

# device properties
ok(acl_matches($dip, [$conf[23]]), '1obj instance anon property deviceport:alias');
ok(acl_matches($dip, ['ip:'.$conf[2]]), '1obj instance named property deviceport:ip');
ok(acl_matches($dip, ['!ip:'. $conf[23]]), '1obj negated instance named property deviceport:ip');
is(acl_matches($dip, ['port:'.$conf[2]]), 0, '1obj failed instance named property deviceport:ip');
ok(acl_matches($dip, ['port:.*GigabitEthernet.*']), '1obj instance named property regexp deviceport:port');

# AND device properties
ok(acl_matches($dip, ['ip:'.$conf[2], '!ip:'. $conf[23], $conf[20]]), 'AND of 1obj instance and negated instance named property deviceport:ip');

# DeviceIp no longer has DevicePort slot accessors
#ok(acl_matches($dip, ['type:l3ipvlan']), '1obj related item field match');
#ok(acl_matches($dip, ['remote_ip:']), '1obj related item field empty');
#ok(acl_matches($dip, ['!type:']), '1obj related item field not empty');
#is(acl_matches($dip, ['foobar:xyz']), 0, '1obj unknown property');

my $dip2 = App::Netdisco::DB->resultset('DeviceIp')->new_result({
   ip   => '127.0.0.1',
   port => 'TenGigabitEthernet1/10',
   alias => '192.0.2.1',
});

my $dp = App::Netdisco::DB->resultset('DevicePort')->new_result({
    ip   => '127.0.0.1',
    port => 'TenGigabitEthernet1/10',
    type => 'l3ipvlan',
    tags => [qw/ foo bar baz /],
    custom_fields => '{"baz": "quux"}',
});


my $d = App::Netdisco::DB->resultset('Device')->new_result({
    ip   => '127.0.0.1',
    dns => 'localhost',
    name => 'mymachine'
    tags => [qw/ quux /],
    custom_fields => '{"foo": "bar"}',
});


# device properties
ok(acl_matches([$dip2, $dp], [$conf[23]]), '2obj instance anon property deviceport:alias');
ok(acl_matches([$dip2, $dp], ['ip:'.$conf[2]]), '2obj instance named property deviceport:ip');
ok(acl_matches([undef, $dip2, $dp], ['ip:'.$conf[2]]), '2obj instance named property after undef');
ok(acl_matches([$dip2, $dp], ['!ip:'. $conf[23]]), '2obj negated instance named property deviceport:ip');
is(acl_matches([$dip2, $dp], ['port:'.$conf[2]]), 0, '2obj failed instance named property deviceport:ip');
ok(acl_matches([$dip2, $dp], ['port:.*GigabitEthernet.*']), '2obj instance named property regexp deviceport:port');

ok(acl_matches([$dip2, $dp], ['type:l3ipvlan']), '2obj related item field match');
ok(acl_matches([$dip2, $dp], ['remote_ip:']), '2obj related item field empty');
ok(acl_matches([$dip2, $dp], ['!type:']), '2obj related item field not empty');
is(acl_matches([$dip2, $dp], ['foobar:xyz']), 0, '2obj unknown property');

my $dip2c = { $dip2->get_inflated_columns };
my $dpc = { $dp->get_inflated_columns };
my $dc = { $d->get_inflated_columns };

# device properties
ok(acl_matches([$dip2c, $dpc], [$conf[23]]), 'hh instance anon property deviceport:alias');
ok(acl_matches([$dip2c, $dpc], ['ip:'.$conf[2]]), 'hh instance named property deviceport:ip');
ok(acl_matches([$dip2c, $dpc], ['!ip:'. $conf[23]]), 'hh negated instance named property deviceport:ip');
is(acl_matches([$dip2c, $dpc], ['port:'.$conf[2]]), 0, 'hh failed instance named property deviceport:ip');
ok(acl_matches([$dip2c, $dpc], ['port:.*GigabitEthernet.*']), 'hh instance named property regexp deviceport:port');

ok(acl_matches([$dip2c, $dpc], ['type:l3ipvlan']), 'hh related item field match');
ok(acl_matches([$dip2c, $dpc], ['remote_ip:']), 'hh related item field empty');
ok(acl_matches([$dip2c, $dpc], ['!type:']), 'hh related item field not empty');
is(acl_matches([$dip2c, $dpc], ['foobar:xyz']), 0, 'hh unknown property');

# device properties
ok(acl_matches([$dip2, $dpc], [$conf[23]]), 'oh instance anon property deviceport:alias');
ok(acl_matches([$dip2, $dpc], ['ip:'.$conf[2]]), 'oh instance named property deviceport:ip');
ok(acl_matches([$dip2, $dpc], ['!ip:'. $conf[23]]), 'oh negated instance named property deviceport:ip');
is(acl_matches([$dip2, $dpc], ['port:'.$conf[2]]), 0, 'oh failed instance named property deviceport:ip');
ok(acl_matches([$dip2, $dpc], ['port:.*GigabitEthernet.*']), 'oh instance named property regexp deviceport:port');

ok(acl_matches([$dip2, $dpc], ['type:l3ipvlan']), 'oh related item field match');
ok(acl_matches([$dip2, $dpc], ['remote_ip:']), 'oh related item field empty');
ok(acl_matches([$dip2, $dpc], ['!type:']), 'oh related item field not empty');
is(acl_matches([$dip2, $dpc], ['foobar:xyz']), 0, 'oh unknown property');

# device properties
ok(acl_matches([$dip2c, $dp], [$conf[23]]), 'ho instance anon property deviceport:alias');
ok(acl_matches([$dip2c, $dp], ['ip:'.$conf[2]]), 'ho instance named property deviceport:ip');
ok(acl_matches([$dip2c, $dp], ['!ip:'. $conf[23]]), 'ho negated instance named property deviceport:ip');
is(acl_matches([$dip2c, $dp], ['port:'.$conf[2]]), 0, 'ho failed instance named property deviceport:ip');
ok(acl_matches([$dip2c, $dp], ['port:.*GigabitEthernet.*']), 'ho instance named property regexp deviceport:port');

ok(acl_matches([$dip2c, $dp], ['type:l3ipvlan']), 'ho related item field match');
ok(acl_matches([$dip2c, $dp], ['remote_ip:']), 'ho related item field empty');
ok(acl_matches([$dip2c, $dp], ['!type:']), 'ho related item field not empty');
is(acl_matches([$dip2c, $dp], ['foobar:xyz']), 0, 'ho unknown property');

# tags

ok(acl_matches([$dip2, $dp], ['tag:foo']), '2obj tag exists');
ok(acl_matches([$dip2, $dp], ['!tag:quux']), '2obj tag not existing');
is(acl_matches([$dp], ['tag:quux']), 0, '1obh tag does not exist');

ok(acl_matches([$dip2c, $dpc], ['tag:foo']), 'hh tag exists');
ok(acl_matches([$dip2c, $dpc], ['!tag:quux']), 'hh tag not existing');
is(acl_matches([$dpc], ['tag:quux']), 0, 'hh tag does not exist');

# custom fields

ok(acl_matches([$dip2, $dp], ['cf:baz:quux']), '2obj cf matches');
ok(acl_matches([$dip2, $dp], ['!cf:baa:qd']), '2obj cf does not match');
is(acl_matches([$dp], ['cf:baa:quux']), 0, '1obh cf does not exist');

ok(acl_matches([$dip2c, $dpc], ['cf:baz:quux']), 'hh cf matches');
ok(acl_matches([$dip2c, $dpc], ['!cf:baa:qd']), 'hh cf does not match');
is(acl_matches([$dpc], ['cf:baa:quux']), 0, 'hh cf does not exist');

ok(acl_matches([$d, $dp], ['op:and','cf:foo:bar','cf:baz:quux']), '2obj cf two rules match');
is(acl_matches([$d, $dp], ['op:and','cf:foo:bar','cf:baa:qd']), 0, '2obj cf two rules do not match');

# cron spec

ok(acl_matches('localhost',[$conf[25]]), 'current time');
is(acl_matches('localhost',[$conf[24]]), 0, 'not current time');

ok(acl_matches('localhost',[$conf[27]]), 'current time');
is(acl_matches('localhost',[$conf[26]]), 0, 'not current time');

is(acl_matches('localhost',[$conf[29]]), 0, '!current time');
ok(acl_matches('localhost',[$conf[28]]), '! not current time');

# device name/dns matching

ok(acl_matches($d, ['local.*']), 'device dns is supposed to match');
is(acl_matches($d, ['notlocalhost']), 0, 'device dns is not supposed to match');
ok(acl_matches($d, ['loc.*host']), 'device dns is supposed to match');

is(acl_matches($d_no_dns, ['local*']), 0, 'device name is not supposed to match');
ok(acl_matches($d_no_dns, ['mymachine']), 'device name is supposed to match name');
is(acl_matches($d_no_dns, ['my*hine']), 0, 'device is supposed to match');

# from bug reports
ok(acl_matches({port => 'FastEthernet10'},[$conf[20],$conf[30],$conf[31]]), '#1348 anded negated prop:val mismatch');
is(acl_matches($dp,[$conf[20],$conf[30],$conf[31]]), 0, '#1348 anded negated prop:val match');

ok(acl_matches({foo => 'FastEthernet10'},[$conf[20],$conf[30],$conf[31]]), '#1348 missing prop matches string if neg is set');
ok(acl_matches($dp,'bar:'), '#1348 missing prop will match if neg is not set');
is(acl_matches($dp,'!bar:'), 0, '#1348 missing prop cannot match if neg is set');

ok(acl_matches($dp,'!cf:foo:asdfasfd'), '#1348 missing cf matches string if neg is set');
ok(acl_matches($dp,'cf:foo:'), '#1348 missing cf will match if neg is not set');
is(acl_matches($dp,'!cf:foo:'), 0, '#1348 missing cf cannot match if neg is set');

done_testing;
