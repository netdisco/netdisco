#!/usr/bin/env perl

# with_layer_features gives the Device Details tab the number of backends
# able to discover, macsuck and arpnip the device, and greys out a button at
# 0. It counted the device's device_skip rows that do not list the action.
# A backend keeps a row for a device only when it holds something against
# it, so a device no backend denies has no row, counted 0, and had all three
# buttons greyed out, while a device denied only arpnip had the other two.
#
# Claims, kept apart:
#   - a device with no row counts every running backend (the faux
#     255.255.255.255 row each one keeps);
#   - a backend whose row lists the action is not counted, for that action
#     only;
#   - every backend denying it counts 0;
#   - a row holding only deferrals denies nothing here.
#
# Needs a database; the rows are made in a transaction that is rolled back.
#
# No DANCER_ENVDIR=/dev/null here: that empties the DSN, and this file needs
# a real one.

use strict;
use warnings;

use Test::More 0.88;

{
    package NetdiscoSchema;
    use App::Netdisco;
    use Dancer qw/:moose :script/;
    use Dancer::Plugin::DBIC 'schema';
    sub connected { my $s = schema('netdisco'); $s->storage->dbh_do(sub { $_[1]->do('SELECT 1') }); return $s }
}

my $schema = eval { NetdiscoSchema::connected() };
my $why = $@;

SKIP: {
    skip "no usable netdisco database: $why", 5 if not $schema;

    my %got;
    eval {
        $schema->txn_do(sub {
            my $skip = $schema->resultset('DeviceSkip');
            # backends running before this test, already counted for any
            # device they hold nothing against
            my $base = $skip->search({ device => '255.255.255.255' })->count;

            $skip->create({ backend => $_, device => '255.255.255.255',
                            deferrals => 1, last_defer => \'LOCALTIMESTAMP' })
              for qw/xt-a xt-b/;

            # 192.0.2.0/24 is documentation space
            my $devices = $schema->resultset('Device');
            $devices->create({ ip => "192.0.2.$_" }) for 1 .. 4;

            # .1: no row anywhere
            # .2: one backend denies macsuck
            $skip->create({ backend => 'xt-a', device => '192.0.2.2' })
              ->add_to_actionset('macsuck');
            # .3: both deny arpnip
            $skip->create({ backend => $_, device => '192.0.2.3' })
              ->add_to_actionset('arpnip') for qw/xt-a xt-b/;
            # .4: deferrals only
            $skip->create({ backend => 'xt-a', device => '192.0.2.4',
                            deferrals => 2, last_defer => \'LOCALTIMESTAMP' });

            foreach my $d ($devices->search({ ip => [ map { "192.0.2.$_" } 1 .. 4 ] })
                                   ->with_layer_features->hri->all) {
                $got{ $d->{ip} } = [ map { $d->{"is_$_"} - $base }
                                     qw/discoverable macsuckable arpnipable/ ];
            }
            die "rollback\n";
        });
    };
    die $@ if $@ and $@ !~ /rollback/;

    is_deeply $got{'192.0.2.1'}, [2, 2, 2],
      'layerFeatures__no_skip_row__every_backend_able';
    is_deeply $got{'192.0.2.2'}, [2, 1, 2],
      'layerFeatures__one_backend_denies_macsuck__that_one_less';
    is_deeply [ @{ $got{'192.0.2.3'} }[2] ], [0],
      'layerFeatures__all_test_backends_deny_arpnip__none_of_them_counted';
    is_deeply [ @{ $got{'192.0.2.3'} }[0, 1] ], [2, 2],
      'layerFeatures__arpnip_denied__other_actions_unchanged';
    is_deeply $got{'192.0.2.4'}, [2, 2, 2],
      'layerFeatures__deferrals_only__denies_nothing';
}

done_testing;
