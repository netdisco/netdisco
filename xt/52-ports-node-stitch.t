#!/usr/bin/env perl

# Task 2 of the Ports tab speedup replaces a three-way prefetch (ports to
# nodes to IPs) with two queries, joined by port name in Perl. This is the
# equivalence check between the two: the stitch must return the same ports,
# in the same order, carrying the same nodes, as the prefetch it replaces.
#
# Note there is no DANCER_ENVDIR=/dev/null here, unlike its neighbours. That
# setting empties the DSN, and this file needs a real one.

use strict;
use warnings;

use Test::More 0.88;

# Dancer's DSL is imported into its own package rather than into main, because
# it exports a `pass` that collides with Test::More's and Perl warns about the
# prototype mismatch.
{
    package NetdiscoSchema;
    use App::Netdisco;
    use Dancer qw/:moose :script/;
    use Dancer::Plugin::DBIC 'schema';
    sub connected { my $s = schema('netdisco'); $s->storage->dbh_do(sub { $_[1]->do('SELECT 1') }); return $s }
}

my $schema = eval { NetdiscoSchema::connected() };
my $why = $@;

# From here on a database is needed. Skipping is reported with the reason
# printed, never silently: a skip that hides a broken connection would leave
# this file green while proving nothing.
SKIP: {
    skip "no usable netdisco database: $why", 4 if not $schema;

    require App::Netdisco::Web::Plugin::Device::Ports;

    my ($device_ip) = $schema->resultset('Virtual::ActiveNode')
      ->search({}, { rows => 1 })->get_column('switch')->all;

    skip 'no device in this database has any active nodes', 4
      if not $device_ip;

    my $device = $schema->resultset('Device')->find($device_ip);
    my $base = $device->ports->with_properties->order_by_port_name;

    my @prefetched = $base->search({}, {
      prefetch => [ { active_nodes => 'ips' } ],
    })->all;

    my @stitched = $base->all;
    App::Netdisco::Web::Plugin::Device::Ports::_stitch_nodes(
      $schema, $device->ip, \@stitched, 'active_nodes', 'ips', [], []);

    # 1. The stitch returns the same ports, in the same order, as the prefetch.
    is_deeply [ map { $_->port } @stitched ], [ map { $_->port } @prefetched ],
      'stitch preserves the port set and the port order';

    # 2. Node sets per port match, compared as sorted MAC lists.
    my %stitched_macs_by_port = map {
        $_->port => [ sort map { $_->{mac} } @{ $_->{stitched_nodes} } ]
    } @stitched;
    my %prefetched_macs_by_port = map {
        $_->port => [ sort map { $_->mac } $_->active_nodes ]
    } @prefetched;
    is_deeply \%stitched_macs_by_port, \%prefetched_macs_by_port,
      'stitch attaches the same nodes to the same ports';

    # 3. The accessor trap: nothing may be attached under a relationship name.
    ok !exists $stitched[0]->{active_nodes},
      'stitched rows are not attached under the has_many accessor name';
    ok !App::Netdisco::DB::Result::DevicePort->can('stitched_nodes'),
      'stitched_nodes is not a method, so Template Toolkit reaches the hash key';
}

done_testing;
