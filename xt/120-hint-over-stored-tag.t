#!/usr/bin/env perl

use strict;
use warnings;

# device_auth_tag_hint is documented to "override, refresh, or reset cached
# authentication for a device", and #1549 introduced it for exactly that: move
# a device answering to two sets of credentials onto the new ones without
# deleting it. Since #1592 the hint only promotes its stanza within the
# configured list, and get_communities puts the last known-good tag and
# community in front of that list, so a device that still answers to the old
# credentials kept them and the hint was never tried.
#
# Asserted on the order get_communities returns, which is the order Transport
# tries. A wrong hint must still fall back to everything else.

use Test::More 0.88;
use App::Netdisco;
use App::Netdisco::Util::SNMP 'get_communities';
use Dancer qw/:script !pass/;

package FakeCommunity;
sub new    { my ($class, %v) = @_; return bless {%v}, $class }
sub snmp_auth_tag_read { return $_[0]->{snmp_auth_tag_read} }
sub snmp_comm_rw       { return $_[0]->{snmp_comm_rw} }
sub update { my ($self, $v) = @_; @$self{keys %$v} = values %$v; return $self }

package FakeDevice;
sub new       { my ($class, %v) = @_; return bless {%v}, $class }
sub ip        { return '192.0.2.1' }
sub dns       { return 'switch1.example.com' }
sub in_storage { return 1 }
sub snmp_comm { return $_[0]->{snmp_comm} }
sub community { return $_[0]->{community} }

package main;

config->{'get_credentials'} = undef;
config->{'get_community'}   = undef;
config->{'device_auth'} = [
  { tag => 'old', community => 'oldcomm', read => 1 },
  { tag => 'new', community => 'newcomm', read => 1 },
  { tag => 'other', community => 'othercomm', read => 1 },
];

# Worker::Runner promotes the hinted stanza before get_communities sees the
# list, so do the same here to get the order a real job tries
sub order {
  my (%opt) = @_;
  local config->{'device_auth_tag_hint'} = $opt{hint};
  my @auth = @{ config->{'device_auth'} };
  my @hinted = grep { $opt{hint} and $_->{tag} eq $opt{hint} } @auth;
  local config->{'device_auth'} = [ @hinted, grep { not ($opt{hint} and $_->{tag} eq $opt{hint}) } @auth ];
  my $device = FakeDevice->new(
    snmp_comm => $opt{snmp_comm},
    community => FakeCommunity->new(snmp_auth_tag_read => $opt{stored}),
  );
  return [ map { $_->{tag} // "comm:$_->{community}" } get_communities($device, 'read') ];
}

is_deeply order(stored => 'old'),
  ['old', 'old', 'new', 'other'],
  'without a hint the stored tag goes first, as before';

is_deeply order(stored => 'old', hint => 'old'),
  ['old', 'old', 'new', 'other'],
  'a hint naming the stored tag changes nothing';

is_deeply order(stored => 'old', hint => 'new'),
  ['new', 'old', 'other'],
  'a hint for another tag is tried before the stored tag, which stays as fallback';

is_deeply order(stored => 'old', hint => 'nosuchtag'),
  ['old', 'old', 'new', 'other'],
  'a hint for a tag that is not configured is ignored';

is_deeply order(snmp_comm => 'oldcomm'),
  ['comm:oldcomm', 'old', 'new', 'other'],
  'without a hint the last known-good v2 community goes first';

is_deeply order(snmp_comm => 'oldcomm', hint => 'new'),
  ['new', 'old', 'other'],
  'a hint goes ahead of the last known-good v2 community too';

done_testing;
