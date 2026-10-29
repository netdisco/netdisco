#!/usr/bin/env perl

# retire_ports is the one place discover removes ports. 'vanished' must send
# plain DELETEs and never reach the delete override (which also removes
# nodes); these assert the SQL, no database needed.

use strict;
use warnings;

use Test::More 0.88;
use App::Netdisco::DB;

my $schema = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $s = App::Netdisco::DB->clone;
  $s->storage_type('::DBI::Pg');
  $s->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $s;
};

my @PORTS = ('Gi0/1', 'Gi0/2');
my @PER_PORT = qw/
  device_port_power device_port_properties device_port_ssid
  device_port_vlan device_port_wireless
/;

{
  package FakeDbh;
  sub new { bless { log => $_[1] }, $_[0] }
  sub do { my ($self, $sql, $attr, @bind) = @_; push @{ $self->{log} }, [ $sql, @bind ]; 7 }
}

sub run_retire {
  my ($ip, $ports, $mode) = @_;
  my (@log, $txns, $override_calls);
  no warnings qw/redefine once/;
  local *DBIx::Class::Storage::DBI::txn_do = sub { $txns++; $_[1]->() };
  local *DBIx::Class::Storage::DBI::dbh_do = sub { $_[1]->($_[0], FakeDbh->new(\@log)) };
  local *App::Netdisco::DB::ResultSet::DevicePort::delete = sub { $override_calls++; die 'override called' };
  my $removed = $schema->resultset('DevicePort')->retire_ports($ip, $ports, $mode);
  return ($removed, \@log, $txns, $override_calls);
}

foreach my $mode (qw/vanished ignored/) {
  subtest "retire_ports__${mode}__deletes_per_port_rows_then_ports" => sub {
    my ($removed, $log, $txns) = run_retire('192.0.2.1', \@PORTS, $mode);
    is(scalar @$log, 6, 'six statements');
    is($txns, 1, 'one transaction');
    my @tables = (@PER_PORT, 'device_port');
    foreach my $index (0 .. $#tables) {
      my ($sql, @bind) = @{ $log->[$index] };
      is($sql, "DELETE FROM $tables[$index] WHERE ip = ? AND port = ANY(?)", "statement $index");
      is_deeply(\@bind, ['192.0.2.1', \@PORTS], "binds $index");
    }
    is($removed, 7, 'returns the device_port delete count');
  };

  subtest "retire_ports__${mode}__never_touches_nodes_or_logs" => sub {
    my (undef, $log) = run_retire('192.0.2.1', \@PORTS, $mode);
    ok(!(grep { $_->[0] =~ /\bnode\b|node_ip|device_port_log/ } @$log), 'no node or log statement');
  };

  subtest "retire_ports__${mode}__bypasses_the_delete_override" => sub {
    my (undef, undef, undef, $override_calls) = run_retire('192.0.2.1', \@PORTS, $mode);
    ok(!$override_calls, 'override not called');
  };
}

subtest 'retire_ports__empty_list__sends_nothing' => sub {
  foreach my $mode (qw/vanished ignored/) {
    my ($removed, $log, $txns) = run_retire('192.0.2.1', [], $mode);
    is($removed, 0, "$mode returns 0");
    is(scalar @$log, 0, "$mode sends no SQL");
    ok(!$txns, "$mode opens no transaction");
  }
};

subtest 'retire_ports__unknown_mode__dies_naming_vanished_and_ignored' => sub {
  foreach my $mode ('gone', undef) {
    eval { run_retire('192.0.2.1', \@PORTS, $mode) };
    like($@, qr/mode must be 'vanished' or 'ignored', got '\Q@{[defined $mode ? $mode : 'undef']}\E'/, 'message');
  }
};

done_testing;
