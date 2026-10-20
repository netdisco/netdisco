#!/usr/bin/env perl

# SNMP::Info's IncompleteWalk default may change from 'partial' to 'undef'.
# Netdisco stores what a table method returns, so it pins the mode itself and
# a later SNMP::Info cannot change what discover and macsuck store.

use strict; use warnings;
no warnings 'once';

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Transport::SNMP ();
use Dancer qw/:moose :script !pass/;

config->{'snmpver'} = 2;

sub connect_args {
  my %captured;
  no warnings 'redefine';
  local *App::Netdisco::Transport::SNMP::load_cache_for_device = sub { {} };
  local *App::Netdisco::Transport::SNMP::get_communities = sub { ({ read => 1, community => 'public' }) };
  local *App::Netdisco::Transport::SNMP::_try_connect = sub { %captured = %{ $_[4] }; return };
  my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });
  App::Netdisco::Transport::SNMP::_snmp_connect_generic('read', $device);
  return \%captured;
}

subtest '_snmp_connect_generic__any_device__passes_IncompleteWalk_partial' => sub {
  is(connect_args()->{IncompleteWalk}, 'partial');
};

subtest '_snmp_connect_generic__net_snmp_options_sets_it__operator_value_wins' => sub {
  local config->{'net_snmp_options'} = { IncompleteWalk => 'undef' };
  is(connect_args()->{IncompleteWalk}, 'undef');
};

done_testing;
