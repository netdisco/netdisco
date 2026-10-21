#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 1.302083;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

BEGIN {
  use_ok( 'App::Netdisco::Configuration' );
  use_ok( 'App::Netdisco::DB' );
  use_ok( 'App::Netdisco::Util::SNMPText', 'snmp_charsets_for' );
  use_ok( 'App::Netdisco::Util::Configuration', 'parse_params_to_config' );
}

use Dancer qw/:script !pass/;

my $any = 'group:__ANY__';

sub normalized {
  my ($raw) = @_;
  config->{'snmp_charset'} = $raw;
  App::Netdisco::Configuration::normalize_snmp_charset();
  return setting('snmp_charset');
}

sub device {
  return App::Netdisco::DB->resultset('Device')->new_result({ @_ });
}

subtest 'snmpCharset__default__is_any_group_with_empty_list' => sub {
  is_deeply( setting('snmp_charset'), [ { $any => [] } ] );
};

subtest 'snmpCharset__scalar_and_single_map__normalize_to_list_of_maps' => sub {
  is_deeply( normalized('gbk'), [ { $any => ['gbk'] } ], 'scalar' );
  is_deeply( normalized({ 'vendor:huawei' => 'gbk' }),
    [ { 'vendor:huawei' => ['gbk'] } ], 'single map with scalar value' );
  is_deeply( normalized([ { 'vendor:huawei' => ['gbk'] }, { $any => 'big5' } ]),
    [ { 'vendor:huawei' => ['gbk'] }, { $any => ['big5'] } ], 'list keeps order' );
};

subtest 'snmpCharset__undef_refs_and_empty__are_dropped' => sub {
  is_deeply( normalized(undef), [ { $any => [] } ], 'undef' );
  is_deeply( normalized([]), [ { $any => [] } ], 'empty list' );
  is_deeply( normalized({ $any => [ 'gbk', undef, '', {}, [], 'big5' ] }),
    [ { $any => [ 'gbk', 'big5' ] } ], 'junk in a charset list' );
  is_deeply( normalized([ undef, [], { $any => undef } ]),
    [ { $any => [] } ], 'undef, list and undef value' );
};

subtest 'snmpCharsetsFor__specific_keys_before_any_group__sorted_and_deduped' => sub {
  normalized({
    $any => ['big5'],
    'vendor:huawei' => ['gbk'],
    '192.0.2.0/24' => [ 'euc-cn', 'gbk' ],
  });
  my $device = device(ip => '192.0.2.1', vendor => 'huawei');
  is_deeply( snmp_charsets_for($device), [ 'euc-cn', 'gbk', 'big5' ] );
};

subtest 'snmpCharsetsFor__no_match__returns_any_group_only' => sub {
  normalized({
    $any => ['big5'],
    'vendor:huawei' => ['gbk'],
  });
  my $device = device(ip => '198.51.100.1', vendor => 'cisco');
  is_deeply( snmp_charsets_for($device), ['big5'] );
};

# a per-job override (-e) is merged into the configuration as written, after
# normalize_snmp_charset has run, so the reader must accept the raw forms too
subtest 'snmpCharsetsFor__job_override_forms__read_without_dying' => sub {
  my $device = device(ip => '192.0.2.1', vendor => 'huawei');
  foreach my $override ('snmp_charset=gbk', '{"snmp_charset":{"vendor:huawei":["gbk"]}}',
                        '{"snmp_charset":{"vendor:huawei":"gbk"}}') {
    normalized(undef);
    parse_params_to_config($override);
    is_deeply( (eval { snmp_charsets_for($device) } || $@), ['gbk'], $override );
  }
};

subtest 'snmpCharsetsFor__undef_device__returns_empty' => sub {
  normalized({ $any => ['big5'] });
  is_deeply( snmp_charsets_for(undef), [] );
};

done_testing;
