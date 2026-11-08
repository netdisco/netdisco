#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::SSHCollector::Platform::NXOS;

# NX-OS logs %VSHD-5-VSHD_SYSLOG_CONFIG_I for a command fed on stdin, as if
# the session had configured the switch (#1783). The same command sent as an
# exec request is not logged, so the capture call must not use stdin_data.

package FakeSSH;
sub new     { my ($class, @lines) = @_; return bless { lines => \@lines }, $class }
sub capture { my $self = shift; $self->{args} = [@_]; return @{ $self->{lines} } }
sub error   { return '' }

package main;

my @table = (
  "   VLAN     MAC Address      Type      age     Secure NTFY Ports\n",
  "---------+-----------------+--------+---------+------+----+------------------\n",
  "+  234     d239.ea50.166a   dynamic  NA         F      F    Po1122\n",
  "* 1509     246e.9618.bc72   dynamic  NA         F      F    Eth1/12\n",
);

my $nxos = App::Netdisco::SSHCollector::Platform::NXOS->new;

subtest 'macsuck__any_table__sends_the_command_as_an_exec_request' => sub {
  my $ssh = FakeSSH->new(@table);
  $nxos->macsuck('nxos-host', $ssh);
  is_deeply($ssh->{args}, ['show mac address-table | no-more'],
    'one plain command string, no stdin_data option');
};

subtest 'macsuck__port_channel_entry__uses_lowercase_port_channel_name' => sub {
  my $entries = $nxos->macsuck('nxos-host', FakeSSH->new(@table));
  is_deeply($entries, {
    234  => { 'port-channel1122' => { 'd2:39:ea:50:16:6a' => 1 } },
    1509 => { 'Ethernet1/12'     => { '24:6e:96:18:bc:72' => 1 } },
  }, 'Po maps to port-channel as NX-OS names it in ifName');
};

subtest 'macsuck__full_word_vlan_port__names_the_svi_once' => sub {
  # NX-OS prints SVI rows as Vlan3001, a full word the map has no key for;
  # the digits were appended a second time, giving Vlan30013001.
  my $entries = $nxos->macsuck('nxos-host', FakeSSH->new(
    "*  3001     5290.faa8.1b08   static   -         F      F    Vlan3001\n",
  ));
  is_deeply($entries, {
    3001 => { 'Vlan3001' => { '52:90:fa:a8:1b:08' => 1 } },
  }, 'Vlan3001 stays Vlan3001');
};

done_testing;
