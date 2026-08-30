#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use FindBin;

BEGIN {
  use Path::Class;
  unshift @INC, dir($FindBin::RealBin)->parent->subdir('lib')->stringify;
  $ENV{DANCER_ENVDIR} = '/dev/null';
}

# The netmap's Neighbor Cloud and Neighbor Hops modes grow a set outward from
# the searched device. The original did it by rescanning every linked device
# once per hop, under a comment that already said `this is O(N^2) or worse`:
#
#     foreach my $cip (keys %cloud) { foreach my $okip (keys %ok_dev) { ... } }
#
# Cost is the sum over passes of |cloud| x |linked devices|. Measured against a
# 6493 device database, where 5523 devices carry links and the cloud saturates
# at 941, ten hops is about 38 million hash lookups, and the request took 12.95
# seconds against 1.15 for one hop. There is no cache in front of it: every
# netmap load pays it again.
#
# A breadth-first walk over an adjacency map is O(links + devices) for the same
# answer. The equivalence is the whole risk of the change, which is why the
# last subtest below runs the original algorithm as an oracle over generated
# graphs rather than asserting hand-picked cases only.
#
# This file needs no database, which is the point of extracting the walk as a
# pure function. Everything around it in that route does need one, and as
# xt/35-login-return-url.t and xt/36-ajax-content-response.t both record, the
# database is what keeps the route itself out of reach here.

use App::Netdisco;
use App::Netdisco::Web::Plugin::Device::Neighbors;

my $walk = \&App::Netdisco::Web::Plugin::Device::Neighbors::neighbors_within_depth;

# the shape the original loop worked from, rebuilt for the oracle
sub oracle {
    my ( $adjacency, $root, $passes ) = @_;
    my %cloud = ( $root => 1 );
    my %linked = map { $_ => 1 } keys %$adjacency;
    my $seen = scalar keys %cloud;

    while ( $seen > 0 and $passes > 0 ) {
        --$passes;
        $seen = 0;
        foreach my $cip ( keys %cloud ) {
            foreach my $okip ( keys %linked ) {
                next if exists $cloud{$okip};
                next unless grep { $_ eq $okip } @{ $adjacency->{$cip} || [] };
                ++$cloud{$okip};
                ++$seen;
            }
        }
    }
    return \%cloud;
}

sub undirected {
    my %adj;
    foreach my $pair ( @_ ) {
        my ( $a, $b ) = @$pair;
        push @{ $adj{$a} }, $b;
        push @{ $adj{$b} }, $a;
    }
    return \%adj;
}

subtest 'neighborsWithinDepth__a_chain__reaches_exactly_the_hops_asked_for' => sub {
    my $chain = undirected( [qw/a b/], [qw/b c/], [qw/c d/], [qw/d e/] );

    is_deeply [ sort keys %{ $walk->( $chain, 'a', 1 ) } ], [qw/a b/],
        'one hop reaches the immediate neighbour';
    is_deeply [ sort keys %{ $walk->( $chain, 'a', 2 ) } ], [qw/a b c/],
        'two hops reach one further';
    is_deeply [ sort keys %{ $walk->( $chain, 'a', 4 ) } ], [qw/a b c d e/],
        'four hops reach the end of the chain';
};

subtest 'neighborsWithinDepth__more_hops_than_the_graph_has__stops_early' => sub {
    my $chain = undirected( [qw/a b/], [qw/b c/] );
    is_deeply [ sort keys %{ $walk->( $chain, 'a', 999 ) } ], [qw/a b c/],
        'a hop count past the end of the graph does not run past the end';
};

subtest 'neighborsWithinDepth__with_no_hop_limit__takes_the_whole_component' => sub {
    # what Neighbor Cloud asks for. It used to pass 999, which is a guess about
    # network diameter rather than a limit anyone chose: measured across every
    # linked device on a 6493 device database as the root, the deepest walk
    # needed 22 hops, so the guess was never reached. A chain longer than 999
    # would have been truncated silently.
    my $chain = undirected( map { [ "d$_", 'd' . ( $_ + 1 ) ] } 1 .. 40 );

    my $unlimited = [ sort keys %{ $walk->( $chain, 'd1', undef ) } ];
    is scalar(@$unlimited), 41, 'an undefined hop count walks the chain to its end';

    is_deeply $unlimited, [ sort keys %{ $walk->( $chain, 'd1', 999 ) } ],
        'and reaches what the old sentinel reached on a graph shorter than it';

    is_deeply [ sort keys %{ $walk->( $chain, 'd1', 3 ) } ],
        [ sort qw/d1 d2 d3 d4/ ],
        'while a defined hop count still stops where it is told';
};

subtest 'neighborsWithinDepth__an_isolated_device__is_just_itself' => sub {
    is_deeply [ keys %{ $walk->( {}, 'lonely', 5 ) } ], ['lonely'],
        'a device with no links maps to itself alone';
};

subtest 'neighborsWithinDepth__a_self_link__does_not_revisit_the_device' => sub {
    my $adj = undirected( [qw/a a/], [qw/a b/] );
    is_deeply [ sort keys %{ $walk->( $adj, 'a', 3 ) } ], [qw/a b/],
        'a device linked to itself is not walked twice';
};

subtest 'neighborsWithinDepth__against_the_original_algorithm__agrees' => sub {
    # deterministic: a fixed seed, so a failure here is reproducible rather
    # than a graph nobody can get back
    srand 20260828;

    my $mismatch = 0;
    foreach my $case ( 1 .. 60 ) {
        my $size = 3 + int rand 12;
        my @names = map { "d$_" } 1 .. $size;
        my @pairs;
        foreach my $i ( 0 .. $#names ) {
            foreach my $j ( $i + 1 .. $#names ) {
                push @pairs, [ $names[$i], $names[$j] ] if rand() < 0.25;
            }
        }
        my $adj = undirected(@pairs);
        foreach my $passes ( 1, 2, 3, 999, undef ) {
            # undef is the no-limit form the cloud mode now passes; the
            # algorithm it replaced had no such form, so 999 is what it is
            # compared against, which these graphs are far shorter than
            my $got  = [ sort keys %{ $walk->( $adj, $names[0], $passes ) } ];
            my $want = [ sort keys %{ oracle( $adj, $names[0], $passes // 999 ) } ];
            my $label = defined $passes ? "$passes passes" : 'no hop limit';
            if ( !is_deeply( $got, $want, "case $case, $label" ) ) {
                $mismatch++;
                diag 'graph: ' . join ' ', map { "$_->[0]-$_->[1]" } @pairs;
            }
            last if $mismatch;
        }
        last if $mismatch;
    }
};

done_testing;
