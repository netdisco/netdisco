#!/usr/bin/env perl

# Backends that share a BACKEND name, such as the replicas of one
# deployment, run PrimeSkiplist at the same time when they start. It wrote
# each device's row with update_or_create, a select then an insert or update,
# in hash order, so the writers raced into "duplicate key value violates
# unique constraint device_skip_pkey" and into deadlocks, and a backend that
# lost wrote no faux 255.255.255.255 row either.
#
# Claims, kept apart:
#   - several workers priming at once all finish, none with an error;
#   - the rows they leave are the denied actions, one row per device;
#   - the faux row is there, holding the worker count;
#   - a second priming updates the rows in place.
#
# Needs a database. The devices and rows are in documentation space and
# removed at the end, as the forked workers cannot share a transaction.
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

    require App::Netdisco::Backend::Job;
    require App::Netdisco::Worker::Plugin::PrimeSkiplist;

    my $backend = 'xt-prime';
    my @ips = map { "198.51.100.$_" } 1 .. 200;

    Dancer::config()->{'workers'}{'BACKEND'} = $backend;
    Dancer::config()->{'macsuck_no'} = ['198.51.100.0/24'];

    my $cleanup = sub {
        $schema->resultset('DeviceSkip')->search({ backend => $backend })->delete;
        $schema->resultset('Device')->search({ ip => \@ips })->delete;
    };
    $cleanup->();
    $schema->resultset('Device')->create({ ip => $_, layers => '00000110' }) for @ips;

    my ($main) = grep { ref }
      @{ Dancer::vars()->{'workers'}{'primeskiplist'}{'main'}{'_base_'}{0} || [] };

    my $prime = sub {
        my $job = App::Netdisco::Backend::Job->new({ job => 0, action => 'primeskiplist' });
        my $status = $main->($job);
        return $status->status;
    };

    # several workers at once, each in its own process and connection; the
    # parent lets go of its connection first, so no child inherits it
    $schema->storage->disconnect;
    my @kids;
    foreach my $n (1 .. 4) {
        my $pid = fork;
        die "fork: $!" unless defined $pid;
        if (not $pid) {
            my $status = eval { $prime->() } || "died: $@";
            exit($status eq 'done' ? 0 : 1);
        }
        push @kids, $pid;
    }
    my @failed = grep { waitpid($_, 0); $? != 0 } @kids;

    is scalar @failed, 0, 'primeSkiplist__four_at_once__all_done';

    my %rows = map { ($_->device => [ sort @{ $_->actionset } ]) }
      $schema->resultset('DeviceSkip')->search({ backend => $backend, device => \@ips })->all;
    is scalar keys %rows, scalar @ips, 'primeSkiplist__four_at_once__one_row_per_device';
    is_deeply $rows{'198.51.100.7'}, ['macsuck', 'nbtstat'],
      'primeSkiplist__four_at_once__row_holds_denied_actions';

    my $faux = $schema->resultset('DeviceSkip')->find({ backend => $backend, device => '255.255.255.255' });
    ok $faux && defined $faux->deferrals, 'primeSkiplist__four_at_once__faux_row_written';

    Dancer::config()->{'macsuck_no'} = [];
    Dancer::config()->{'arpnip_no'} = ['198.51.100.0/24'];
    $prime->();
    my $row = $schema->resultset('DeviceSkip')->find({ backend => $backend, device => '198.51.100.7' });
    is_deeply [ sort @{ $row->actionset } ], ['arpnip'],
      'primeSkiplist__again__row_updated_in_place';

    $faux->delete if $faux;
    $cleanup->();
}

done_testing;
