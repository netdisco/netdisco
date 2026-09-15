#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile catdir updir/;
use FindBin;
use Template::AutoFilter;

# The device Modules tab groups a parent's children by class, and those class
# names live in a hash. Perl randomises hash iteration per process, so before
# this was fixed the tree rendered in a different order on every web process
# restart: same modules, same count, shuffled. That is a production symptom and
# not merely a testing one, and it is why the visual harness has to pin
# PERL_HASH_SEED to compare captures at all.
#
# ajax/device/modules.tt walks the classes with .keys.sort, and the order that
# produces is the same one Device/Modules.pm already asks the database for:
# order_by parent, class, pos, index, on a text column, which is alphabetical.
# Sorting the keys restores that rather than inventing an order of its own.
#
# Alphabetical is deterministic, not meaningful. On hardware where a chassis
# holds line cards, "fan" sorts above "module", which is not how anyone reads a
# device. Ordering by ENTITY-MIB class rank instead is a real improvement and a
# separate question; this file only pins down that the order is stable.

my $views = catdir( $FindBin::Bin, updir(), 'share', 'views' );

sub engine {
    # Mirrors xt/lib/Test/Netdisco/Snapshot.pm's _engine, which in turn mirrors
    # the application's own Template configuration.
    return Template::AutoFilter->new({
        INCLUDE_PATH => [$views],
        START_TAG    => quotemeta('[%'),
        END_TAG      => quotemeta('%]'),
        ANYCASE      => 1,
        ABSOLUTE     => 1,
        PRE_CHOMP    => 1,
        AUTO_FILTER  => 'html_entity',
        ENCODING     => 'utf8',
    });
}

# Six sibling classes under one chassis, deliberately not built in alphabetical
# order. Six rather than three on purpose: this render is the end-to-end proof
# that the sort takes effect, but on its own it is only a probabilistic guard
# against the sort being removed, because an unsorted hash could still come out
# alphabetical by luck. Six classes make that one chance in 720 instead of one
# in six. The deterministic guard is the source assertion at the end.
my %CHILD = (
    sensor      => [ 10, 'SENSOR-ITEM' ],
    fan         => [ 20, 'FAN-ITEM' ],
    powerSupply => [ 30, 'POWERSUPPLY-ITEM' ],
    module      => [ 40, 'MODULE-ITEM' ],
    container   => [ 50, 'CONTAINER-ITEM' ],
    backplane   => [ 60, 'BACKPLANE-ITEM' ],
);

my $nodes = {
    root => [1],
    1 => {
        module   => { description => 'CHASSIS-ITEM' },
        children => { map { $_ => [ $CHILD{$_}[0] ] } keys %CHILD },
    },
    map { $CHILD{$_}[0] => { module => { description => $CHILD{$_}[1] } } } keys %CHILD,
};

sub render {
    my $out = '';
    # No $Template::Stash::PRIVATE dance here, unlike the snapshot helper: that
    # exists so settings._foo keys resolve, and nothing in this stash starts
    # with an underscore.
    my $ok = engine()->process( 'ajax/device/modules.tt', {
        nodes   => $nodes,
        uri_for => sub { $_[0] },
    }, \$out );
    return $ok ? $out : die engine()->error;
}

subtest 'moduleTree__children_of_one_parent__render_in_class_order' => sub {
    my $html = render();

    my @seen = $html =~ m/\b([A-Z]+-ITEM)\b/g;
    my %first;
    my @order = grep { !$first{$_}++ } @seen;

    is shift(@order), 'CHASSIS-ITEM', 'the root renders first, above its children';

    my @expected = map { $CHILD{$_}[1] } sort keys %CHILD;
    is_deeply \@order, \@expected,
        'sibling classes render in sorted class order: '
      . join( ', ', sort keys %CHILD );
};

subtest 'moduleTree__template_source__asks_for_sorted_class_keys' => sub {
    # The render above cannot prove this on its own. Hash order is fixed for a
    # given set of keys within a process, so a test cannot vary it the way a
    # server restart does; the only way to observe the original defect is to
    # boot the application twice under different PERL_HASH_SEED values, which is
    # out of reach here. This assertion is what actually fails if the sort is
    # removed.
    my $tt = catfile( $views, 'ajax', 'device', 'modules.tt' );
    my $source = do {
        open my $fh, '<', $tt or die "cannot read $tt: $!";
        local $/;
        <$fh>;
    };

    like $source, qr/children\.keys\.sort/,
        'the class keys are sorted before iteration. Without this the tree '
      . 'reorders on every web process restart.';
};

done_testing;
