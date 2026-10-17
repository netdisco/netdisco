#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 1.302083;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };
use Encode ();

BEGIN {
  use_ok( 'App::Netdisco::Configuration' );
  use_ok( 'App::Netdisco::Util::SNMPText', ':all' );
}

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Worker::Plugin::Discover::Properties ();
use App::Netdisco::Worker::Plugin::Macsuck::Nodes ();
use Dancer qw/:script !pass/;

no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

my %words = (
  nihao  => "\x{4f60}\x{597d}",
  cafe   => "caf\x{e9}",
  muller => "M\x{fc}ller",
);

sub sent_as {
  my ($word, $encoding) = @_;
  return Encode::encode($encoding, $words{$word}, Encode::FB_CROAK | Encode::LEAVE_SRC);
}

# expected results, measured 2026-10-17
my %expect = (   # [word, sent_as, fallbacks] => [result_is_word, how]
  'nihao UTF-8 []'      => [1, 'UTF-8'],   'nihao UTF-8 gbk'      => [1, 'UTF-8'],
  'nihao gbk []'        => [0, 'latin1'],  'nihao gbk gbk'        => [1, 'gbk'],
  'cafe UTF-8 []'       => [1, 'UTF-8'],   'cafe iso-8859-1 []'   => [1, 'latin1'],
  'cafe iso-8859-1 gbk' => [1, 'latin1'],  'cafe gbk []'          => [0, 'latin1'],
  'cafe gbk gbk'        => [1, 'gbk'],     'muller UTF-8 gbk'     => [1, 'UTF-8'],
  'muller iso-8859-1 []'=> [1, 'latin1'],
  'muller iso-8859-1 gbk' => [0, 'gbk'],   # documented limitation: fc6c is valid GBK
  'muller gbk gbk'      => [1, 'gbk'],
);

subtest 'decodeSnmpText__matrix__matches_spec' => sub {
  foreach my $key (sort keys %expect) {
    my ($word, $encoding, $fallback) = split ' ', $key;
    my $bytes = sent_as($word, $encoding);
    my $charsets = ($fallback eq '[]') ? [] : [$fallback];
    my ($text, $how) = decode_text_with($bytes, $charsets);
    my ($is_word, $want_how) = @{ $expect{$key} };
    is($text eq $words{$word} ? 1 : 0, $is_word, "$key: result");
    is($how, $want_how, "$key: how");
  }
};

is(scalar decode_text_with("\xc4\xe3\xba\xc3", ['gbk']), "\x{4f60}\x{597d}",
  'decodeSnmpText__reporter_gbk_bytes__decode_with_gbk');

subtest 'decodeSnmpText__ascii__returned_as_is_with_how_ascii' => sub {
  my ($text, $how) = decode_text_with('plain text', ['gbk']);
  is($text, 'plain text');
  is($how, 'ascii');
};

subtest 'decodeSnmpText__empty_and_undef__returned_unchanged' => sub {
  is(scalar decode_text_with('', ['gbk']), '');
  ok(!defined scalar decode_text_with(undef, ['gbk']));
  is(scalar decode_snmp_text('', undef, 'name'), '');
  ok(!defined decode_snmp_text(undef, undef, 'name'));
};

subtest 'decodeSnmpText__failed_decode__leaves_input_bytes_intact' => sub {
  my $latin1_cafe = "caf\xe9";
  decode_text_with($latin1_cafe, ['gbk']);
  is($latin1_cafe, "caf\xe9");
};

subtest 'decodeSnmpText__truncated_gbk__rejected_by_round_trip' => sub {
  my (undef, $how) = decode_text_with("\xc4\xe3\xba", ['gbk']);
  is($how, 'latin1');
};

subtest 'decodeSnmpText__lone_ff__rejected_by_round_trip' => sub {
  my (undef, $how) = decode_text_with("a\xffb", ['gbk']);
  is($how, 'latin1');
};

subtest 'decodeSnmpText__unknown_charset__warns_once_and_is_skipped' => sub {
  my @warnings;
  local *App::Netdisco::Util::SNMPText::warning = sub { push @warnings, @_ };
  my @hows = map { (decode_text_with("caf\xe9", ['no-such-charset']))[1] } 1, 2;
  like($_, qr/^(?:UTF-8|latin1)$/) for @hows;
  is(scalar @warnings, 1, 'exactly one warning');
};

subtest 'decodeSnmpText__already_decoded_string__returned_unchanged' => sub {
  my $decoded = "caf\x{e9} \x{4f60}";
  ok(utf8::is_utf8($decoded));
  is(scalar decode_text_with($decoded, ['gbk']), $decoded);
};

subtest 'decodeSnmpText__latin1_fallback__logs_debug_with_hex' => sub {
  my @messages;
  local *App::Netdisco::Util::SNMPText::debug = sub { push @messages, @_ };
  is(decode_snmp_text("caf\xe9", undef, 'name'), "caf\x{e9}");
  is(scalar @messages, 1);
  like($messages[0], qr/\[-\] name bytes 636166e9 are not UTF-8/);
};

package FakeSNMP;
sub new { my ($class, %vals) = @_; return bless {%vals}, $class }
our $AUTOLOAD;
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  return $self->{$method};
}

package main;

sub device_text_value {
  return App::Netdisco::Worker::Plugin::Discover::Properties::_device_text_value(@_);
}

sub discovered_device {
  return App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1', @_ });
}

sub charset_lookups_for {
  my ($bytes, $device) = @_;
  my $lookups = 0;
  no warnings 'redefine';
  my $real = \&App::Netdisco::Util::SNMPText::snmp_charsets_for;
  local *App::Netdisco::Util::SNMPText::snmp_charsets_for = sub { $lookups++; $real->(@_) };
  my $text = decode_snmp_text($bytes, $device, 'name');
  return ($lookups, $text);
}

subtest 'decodeSnmpText__ascii__does_not_look_up_charsets' => sub {
  my ($lookups) = charset_lookups_for('GigabitEthernet0/1', discovered_device());
  is($lookups, 0);
};

subtest 'decodeSnmpText__valid_utf8__does_not_look_up_charsets' => sub {
  my ($lookups, $text) = charset_lookups_for(sent_as('nihao', 'UTF-8'), discovered_device());
  is($lookups, 0);
  is($text, $words{nihao});
};

subtest 'decodeSnmpText__gbk_with_huawei_charset__looks_up_charsets_once' => sub {
  config->{'snmp_charset'} = { 'vendor:huawei' => ['gbk'] };
  App::Netdisco::Configuration::normalize_snmp_charset();
  my ($lookups, $text) = charset_lookups_for("\xc4\xe3\xba\xc3", discovered_device(vendor => 'huawei'));
  is($lookups, 1);
  is($text, $words{nihao});
  config->{'snmp_charset'} = { 'group:__ANY__' => [] };
  App::Netdisco::Configuration::normalize_snmp_charset();
};

subtest 'deviceTextProperties__gbk_sysname_with_huawei_charset__decodes' => sub {
  config->{'snmp_charset'} = { 'vendor:huawei' => ['gbk'] };
  App::Netdisco::Configuration::normalize_snmp_charset();
  my $snmp = FakeSNMP->new(name => "\xc4\xe3\xba\xc3");
  is(device_text_value($snmp, 'name', discovered_device(vendor => 'huawei')),
    $words{nihao});
  config->{'snmp_charset'} = { 'group:__ANY__' => [] };
  App::Netdisco::Configuration::normalize_snmp_charset();
};

subtest 'deviceTextProperties__utf8_sysdescr__not_double_encoded' => sub {
  my $snmp = FakeSNMP->new(description => sent_as('cafe', 'UTF-8'));
  my $text = device_text_value($snmp, 'description', discovered_device());
  is($text, $words{cafe});
  is(length $text, 4);
};

subtest 'deviceTextProperties__hash_valued_property__stays_undef' => sub {
  my $snmp = FakeSNMP->new(
    os       => { 1 => 'HASH(0x55d0c0ffee)' },
    location => 'HASH(0x55d0c0ffee)',
  );
  ok(!defined device_text_value($snmp, 'os', discovered_device()), 'hash of HASH text');
  ok(!defined device_text_value($snmp, 'location', discovered_device(), 1), 'trimmed member');
};

subtest 'deviceTextProperties__latin1_contact__is_muller_not_replacement_char' => sub {
  my $snmp = FakeSNMP->new(contact => sent_as('muller', 'iso-8859-1'));
  is(device_text_value($snmp, 'contact', discovered_device(), 1), $words{muller});
};

subtest 'deviceTextProperties__whitespace_and_absent__keep_their_old_shapes' => sub {
  my $snmp = FakeSNMP->new(location => "Lab 1  \n", description => "Lab 1 ");
  is(device_text_value($snmp, 'location', discovered_device(), 1), 'Lab 1', 'trimmed member is trimmed');
  is(device_text_value($snmp, 'contact', discovered_device(), 1), '', 'absent trimmed member is empty');
  is(device_text_value($snmp, 'description', discovered_device()), 'Lab 1 ', 'raw member is not trimmed');
  ok(!defined device_text_value($snmp, 'name', discovered_device()), 'absent raw member is undef');
};

subtest 'sweep__no_lossy_utf8_decode__remains_in_workers' => sub {
  require File::Find;
  my @offenders;
  File::Find::find({ no_chdir => 1, wanted => sub {
    return unless /\.pm$/;
    return if $File::Find::name =~ m{Util/SNMPText\.pm$};
    open my $source, '<', $File::Find::name or die "$File::Find::name: $!";
    while (my $line = <$source>) {
      push @offenders, "$File::Find::name:$.: $line"
        if $line =~ m/Encode::decode\(\s*'UTF-8'/;
    }
  } }, 'lib/App/Netdisco/Worker', 'lib/App/Netdisco/Util');
  is_deeply(\@offenders, [], 'no lossy UTF-8 decode outside Util/SNMPText.pm')
    or diag @offenders;
};

subtest 'macsuckVlanList__non_ascii_vlan_name__matches_macsuck_no_vlan' => sub {
  my $snmp = FakeSNMP->new(
    cisco_comm_indexing => 1,
    i_vlan              => { 1 => 5, 2 => 6 },
    v_name              => { 5 => sent_as('cafe', 'UTF-8'), 6 => 'plain' },
  );
  config->{'macsuck_no_vlan'} = [ $words{cafe} ];
  my @ok = App::Netdisco::Worker::Plugin::Macsuck::Nodes::get_vlan_list($snmp, discovered_device());
  delete config->{'macsuck_no_vlan'};
  is_deeply([sort @ok], [6], 'the VLAN named with UTF-8 bytes is skipped');
};

done_testing;
