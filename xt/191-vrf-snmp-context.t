#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Util::SNMP qw/snmp_vrf_context snmp_vrf_reindex/;
use Path::Class 'file';

package FakeSNMP;
# snmp_comm is fixed at construction in real SNMP::Info; update() replaces
# only the session
sub new {
  my ($class, %vals) = @_;
  return bless {session => {Community => 'labro', Context => ''}, updates => [], %vals}, $class;
}
sub snmp_ver { $_[0]{snmp_ver} || 2 }
sub snmp_comm { 'labro' }
sub vtp_version { undef }
sub class { 'SNMP::Info::Layer3::Fake' }
sub cache { }
sub session { $_[0]{session} }
sub update {
  my ($self, %args) = @_;
  push @{ $self->{updates} }, {%args};
  # SNMP::Info::update() keeps the old session and returns false on failure
  return if $self->{fail_update};
  $self->{session}{$_} = $args{$_} for keys %args;
  return $self->{session};
}

package main;

my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });
my $red = { name => 'red', contexts => [{ kind => 'vrf', id => 'red', v2c => '%s@red', v3 => 'red' }] };

subtest 'snmp_vrf_context__v3__sets_context_name' => sub {
  my $snmp = FakeSNMP->new(snmp_ver => 3);
  ok snmp_vrf_context($snmp, $device, $red), 'returns true';
  is_deeply $snmp->{updates}, [{ Context => 'red' }], 'context set to the v3 name';
};

subtest 'snmp_vrf_context__v2c_template__formats_community' => sub {
  my $snmp = FakeSNMP->new;
  ok snmp_vrf_context($snmp, $device, $red), 'returns true';
  is_deeply $snmp->{updates}, [{ Community => 'labro@red' }], 'template filled with the community';
};

subtest 'snmp_vrf_context__v2c_without_template__false_and_session_untouched' => sub {
  my $snmp = FakeSNMP->new;
  my $nxos = { name => 'red', contexts => [{ kind => 'vrf', id => 'red', v2c => undef, v3 => 'red' }] };
  is snmp_vrf_context($snmp, $device, $nxos), undef, 'returns undef, apart from a failed update';
  is_deeply $snmp->{updates}, [], 'no update issued';
};

subtest 'snmp_vrf_context__v3_without_name__false_and_session_untouched' => sub {
  my $snmp = FakeSNMP->new(snmp_ver => 3);
  my $nameless = { name => 'red', contexts => [{ kind => 'vrf', id => 'red', v2c => '%s@red', v3 => undef }] };
  is snmp_vrf_context($snmp, $device, $nameless), undef, 'returns undef, apart from a failed update';
  is_deeply $snmp->{updates}, [], 'no update issued';
};

subtest 'snmp_vrf_context__attribution_mode__reads_in_default_context' => sub {
  foreach my $record ({ name => 'red', contexts => [] }, { name => 'red' },
                      { name => 'default', contexts => [{ kind => 'none' }] }) {
    my $snmp = FakeSNMP->new;
    ok snmp_vrf_context($snmp, $device, $record), 'returns true';
    is $snmp->session->{Community}, 'labro', 'plain community in use';
  }
};

subtest 'snmp_vrf_context__default_record_after_switch__restores_default' => sub {
  my $snmp = FakeSNMP->new;
  snmp_vrf_context($snmp, $device, $red);
  ok snmp_vrf_context($snmp, $device, { name => 'default', contexts => [{ kind => 'none' }] }), 'true';
  is $snmp->session->{Community}, 'labro', 'plain community restored';
};

subtest 'snmp_vrf_context__undef__restores_default' => sub {
  my $v2 = FakeSNMP->new;
  snmp_vrf_context($v2, $device, $red);
  ok snmp_vrf_context($v2, $device, undef), 'returns true';
  is_deeply $v2->{updates}, [{ Community => 'labro@red' }, { Community => 'labro' }], 'restoring update issued';

  my $v3 = FakeSNMP->new(snmp_ver => 3);
  snmp_vrf_context($v3, $device, $red);
  snmp_vrf_context($v3, $device, undef);
  is_deeply $v3->{updates}, [{ Context => 'red' }, { Context => '' }], 'v3 context cleared';
};

subtest 'snmp_vrf_context__undef_after_snmp_vrf_reindex__still_restores' => sub {
  my $snmp = FakeSNMP->new;
  snmp_vrf_reindex($snmp, $device, 'red');
  snmp_vrf_reindex($snmp, $device, 0);
  snmp_vrf_context($snmp, $device, $red);
  snmp_vrf_context($snmp, $device, undef);
  is $snmp->session->{Community}, 'labro', 'plain community restored';
  is_deeply $snmp->{updates}->[-1], { Community => 'labro' }, 'last update is the restore';
};

subtest 'snmp_vrf_context__switch_between_vrfs__formats_from_plain_community' => sub {
  my $snmp = FakeSNMP->new;
  snmp_vrf_context($snmp, $device, $red);
  snmp_vrf_context($snmp, $device, { name => 'blue', contexts => [{ kind => 'vrf', id => 'blue', v2c => '%s@blue', v3 => 'blue' }] });
  is_deeply $snmp->{updates}, [{ Community => 'labro@red' }, { Community => 'labro@blue' }], 'each switch uses snmp_comm';
};

subtest 'snmp_vrf_context__update_fails__returns_0' => sub {
  foreach my $ver (2, 3) {
    my $snmp = FakeSNMP->new(snmp_ver => $ver, fail_update => 1);
    is snmp_vrf_context($snmp, $device, $red), 0, "v$ver switch that did not take returns 0";
    is $snmp->session->{Community}, 'labro', "v$ver session still in the default context";
  }
};

subtest 'snmp_vrf_context__restore_update_fails__returns_0' => sub {
  my $snmp = FakeSNMP->new;
  snmp_vrf_context($snmp, $device, $red);
  $snmp->{fail_update} = 1;
  is snmp_vrf_context($snmp, $device, undef), 0, 'restore that did not take returns 0';
};

subtest 'snmp_vrf_context__never_concatenates_community_at_name' => sub {
  my $source = file('lib/App/Netdisco/Util/SNMP.pm')->slurp;
  my ($body) = $source =~ m/^sub snmp_vrf_context \{(.*?)^\}/ms;
  ok defined $body, 'found the sub';
  unlike $body, qr/'\@'\s*\./, 'no community . "@" . name concatenation';
};

done_testing;
