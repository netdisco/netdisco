#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Util::SNMP qw/snmp_comm_reindex snmp_vrf_reindex/;
use App::Netdisco::Worker::Plugin::Discover::Properties ();
use Dancer qw/:moose :script !pass/;

# A Nexus answers each VRF's SNMP context for IP-MIB, and a context the device
# does not map answers nothing, so SNMP::Info's interfaces() returns undef.
# Context "" is the default VRF.

config->{'device_auth'} = [{tag => 'lab', community => 'labro'}];

package FakeSNMP;
sub new { my ($class, %vals) = @_; return bless {context => '', %vals}, $class }
sub snmp_ver { $_[0]{snmp_ver} || 2 }
sub snmp_comm { 'labro' }
sub vtp_version { undef }
sub class { 'SNMP::Info::Layer3::Nexus' }
sub cache { }
sub cisco_comm_indexing { 1 }
sub vrf_name { { '3.114.101.100' => 'red', '4.98.108.117.101' => 'blue' } }
sub update {
  my ($self, %args) = @_;
  $self->{context} = exists $args{Context} ? $args{Context}
    : ($args{Community} =~ m/\@(.+)$/ ? $1 : '');
  push @{ $self->{contexts_asked} }, $self->{context};
}
sub _answer { my ($self, $table) = @_; return $self->{answers}{ $self->{context} }{$table} }
sub ip_index   { $_[0]->_answer('ip_index') }
sub ip_table   { $_[0]->_answer('ip_table') }
sub ip_netmask { $_[0]->_answer('ip_netmask') }
sub interfaces { $_[0]->_answer('interfaces') }
sub ipv6_index { $_[0]->_answer('ipv6_index') }
sub ipv6_addr  { $_[0]->_answer('ipv6_addr') }
sub ipv6_type  { $_[0]->_answer('ipv6_type') }
sub ipv6_addr_prefixlength { $_[0]->_answer('ipv6_pfxlen') }

package main;

my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });

my %red_only = (
  '' => { ip_index => {}, ip_table => {}, ip_netmask => {}, interfaces => { 1 => 'mgmt0' },
          ipv6_index => {}, ipv6_addr => {}, ipv6_type => {}, ipv6_pfxlen => {} },
  red => { ip_index => { '10.10.10.1' => 7 }, ip_table => { '10.10.10.1' => '10.10.10.1' },
           ip_netmask => { '10.10.10.1' => '255.255.255.0' }, interfaces => { 7 => 'Ethernet1/1' },
           ipv6_index => { '7.1' => 7 }, ipv6_addr => { '7.1' => '2001:db8::1' },
           ipv6_type => { '7.1' => 'unicast' }, ipv6_pfxlen => { '7.1' => 64 } },
  blue => {},
);

subtest 'getIpv4Aliases__one_vrf_context_unanswered__keeps_the_answering_vrf' => sub {
  my $snmp = FakeSNMP->new(answers => \%red_only);
  my @aliases = eval { App::Netdisco::Worker::Plugin::Discover::Properties::_get_ipv4_aliases($device, $snmp) };
  is $@, '', 'discover does not die';
  is_deeply \@aliases,
    [{ alias => '10.10.10.1', port => 'Ethernet1/1', subnet => '10.10.10.0/24', dns => undef }],
    'red VRF address is kept with its port and subnet';
};

subtest 'getIpv4Aliases__default_context_answers_nothing__keeps_the_vrf_addresses' => sub {
  my $snmp = FakeSNMP->new(answers => { %red_only, '' => {} });
  my @aliases = eval { App::Netdisco::Worker::Plugin::Discover::Properties::_get_ipv4_aliases($device, $snmp) };
  is $@, '', 'discover does not die';
  is_deeply [map { $_->{alias} } @aliases], ['10.10.10.1'], 'red VRF address is kept';
};

subtest 'getIpv6Aliases__one_vrf_context_unanswered__keeps_the_answering_vrf' => sub {
  my $snmp = FakeSNMP->new(answers => \%red_only);
  my @aliases = eval { App::Netdisco::Worker::Plugin::Discover::Properties::_get_ipv6_aliases($device, $snmp) };
  is $@, '', 'discover does not die';
  is scalar(@aliases), 1, 'one address';
  is $aliases[0]{port}, 'Ethernet1/1', 'red VRF address keeps its port';
};

foreach my $vrf (qw/red prod-red prod_red prod.red 100/) {
  subtest "snmpVrfReindex__v3_vrf_named_${vrf}__uses_the_name_as_the_context" => sub {
    my $snmp = FakeSNMP->new(snmp_ver => 3);
    snmp_vrf_reindex($snmp, $device, $vrf);
    is $snmp->{context}, $vrf, 'context is the VRF name, with no VLAN prefix';
  };
}

subtest 'snmpVrfReindex__v2c_vrf__uses_community_at_vrf' => sub {
  my $snmp = FakeSNMP->new(snmp_ver => 2);
  snmp_vrf_reindex($snmp, $device, 'prod-red');
  is $snmp->{context}, 'prod-red', 'community labro@prod-red';
};

subtest 'snmpCommReindex__v3_numeric_vlan__uses_the_vlan_prefix' => sub {
  my $snmp = FakeSNMP->new(snmp_ver => 3);
  snmp_comm_reindex($snmp, $device, 10);
  is $snmp->{context}, 'vlan-10', 'context is vlan-10';
};

subtest 'snmpCommReindex__v3_vrf_name__still_uses_the_name_as_the_context' => sub {
  my $snmp = FakeSNMP->new(snmp_ver => 3);
  snmp_comm_reindex($snmp, $device, 'red');
  is $snmp->{context}, 'red', 'callers outside this distribution may pass VRF names here';
};

subtest 'snmpCommReindex__v3_zero__resets_to_the_default_context' => sub {
  my $snmp = FakeSNMP->new(snmp_ver => 3, context => 'red');
  snmp_comm_reindex($snmp, $device, 0);
  is $snmp->{context}, '', 'empty context';
};

done_testing;
