#!/usr/bin/env perl

# Deleting or archiving one switch's nodes reached the same MACs on other
# switches: archiving matched on MAC alone, and the plain delete kept node_ip
# rows only when another node had the MAC on a port of another name, so the
# same port name on another switch did not count. A host that moved to a new
# switch then showed as archived there, or lost its IP history.
#
# Needs a database; runs inside a transaction that is rolled back.

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

my $old   = '192.0.2.1';
my $new   = '192.0.2.2';
my $moved = '02:00:00:00:00:01';
my $stays = '02:00:00:00:00:02';

sub seed {
    my $node = $schema->resultset('Node');
    $node->create({ mac => $moved, switch => $old, port => 'Gi1/1', vlan => '1', active => 1 });
    $node->create({ mac => $moved, switch => $new, port => 'Gi1/1', vlan => '1', active => 1 });
    $node->create({ mac => $stays, switch => $old, port => 'Gi1/2', vlan => '1', active => 1 });
    foreach my $mac ($moved, $stays) {
        my $n = substr($mac, -1);
        $schema->resultset('NodeIp')->create({ mac => $mac, ip => "198.51.100.$n", vrf => '', active => 1 });
        $schema->resultset('NodeNbt')->create({ mac => $mac, ip => "198.51.100.$n", active => 1 });
        $schema->resultset('NodeWireless')->create({ mac => $mac, ssid => 'test' });
    }
}

sub in_txn {
    my $code = shift;
    $schema->txn_do(sub { seed(); $code->(); die "rollback\n" });
}

sub active {
    my ($set, %cond) = @_;
    my $row = $schema->resultset($set)->search(\%cond)->single;
    return $row ? ($row->active ? 'active' : 'archived') : 'gone';
}

sub count { my ($set, %cond) = @_; $schema->resultset($set)->search(\%cond)->count }

SKIP: {
    skip "no usable netdisco database: $why", 2 if not $schema;

    subtest 'archive__only_the_deleted_switch' => sub {
        eval { in_txn(sub {
            $schema->resultset('Node')->search({ switch => $old })
              ->delete({ archive_nodes => 1 });

            is active('Node', mac => $moved, switch => $old), 'archived', 'old switch node archived';
            is active('Node', mac => $moved, switch => $new), 'active', 'new switch node still active';
            is active('NodeIp', mac => $moved), 'active', 'moved host keeps its IP active';
            is active('NodeNbt', mac => $moved), 'active', 'moved host keeps its NetBIOS active';
            is count('NodeWireless', mac => $moved), 1, 'moved host keeps its wireless row';

            is active('NodeIp', mac => $stays), 'archived', 'host only on old switch: IP archived';
            is active('NodeNbt', mac => $stays), 'archived', 'host only on old switch: NetBIOS archived';
            is count('NodeWireless', mac => $stays), 0, 'host only on old switch: wireless removed';
        }) };
        like $@, qr/^(?:\{UNKNOWN\}: )?rollback/, 'ran and rolled back';
    };

    subtest 'delete__same_port_name_on_another_switch' => sub {
        eval { in_txn(sub {
            $schema->resultset('Node')->search({ switch => $old })->delete;

            is count('Node', switch => $old), 0, 'old switch nodes deleted';
            is active('Node', mac => $moved, switch => $new), 'active', 'new switch node untouched';
            is count('NodeIp', mac => $moved), 1, 'moved host keeps its IP';
            is count('NodeNbt', mac => $moved), 1, 'moved host keeps its NetBIOS';
            is count('NodeWireless', mac => $moved), 1, 'moved host keeps its wireless row';

            is count('NodeIp', mac => $stays), 0, 'host only on old switch: IP deleted';
            is count('NodeNbt', mac => $stays), 0, 'host only on old switch: NetBIOS deleted';
            is count('NodeWireless', mac => $stays), 0, 'host only on old switch: wireless deleted';
        }) };
        like $@, qr/^(?:\{UNKNOWN\}: )?rollback/, 'ran and rolled back';
    };
}

done_testing;
