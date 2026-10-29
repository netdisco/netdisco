#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Backend::Job;
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Worker::Plugin::Discover::Neighbors ();
use DBIx::Class::SQLMaker;

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# The Neighbors worker runs for real with SNMP stubbed. Each DevicePort
# search-and-update is rendered to SQL by DBIx::Class::SQLMaker and recorded,
# so the WHERE that decides which rows are written is checked without a
# database. Ports no longer lose remote_* and is_uplink to a delete and
# reinsert each discover, so Neighbors clears them itself.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

config->{'device_auth'} = [{driver => 'snmp'}];
config->{'enable_incomplete_walk_protection'} = 1;
config->{'queue_neighbors'} = 1;
config->{'discover_neighbors'} = 1;

package FakeSNMP;
our $AUTOLOAD;
sub new { my ($class, %vals) = @_; return bless { walk_failures => [], %vals }, $class; }
sub walk_failures { $_[0]{walk_failures} }
sub walk_status { $_[0]{walk_status}{$_[1]} }
sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  if (my $failure = delete $self->{fail_on_read}{$method}) {
    push @{ $self->{walk_failures} }, $failure;
    $self->{walk_status}{$method} = $failure;
  }
  return $self->{$method};
}

package FakePortRow;
sub new { my ($class, %cols) = @_; return bless { manual_topo => 0, %cols }, $class; }
sub port { $_[0]{port} }
sub manual_topo { $_[0]{manual_topo} }
sub slave_of { $_[0]{slave_of} }
sub is_master { $_[0]{is_master} }
sub remote_port { $_[0]{remote_port} }
sub discard_changes { $_[0] }
sub update {
  my ($self, $values) = @_;
  push @main::row_updates,
    [ $self->{owner}, $self->{port}, $values, $self, { map {($_ => $self->{$_})} keys %$values } ];
  foreach my $col (keys %$values) {
    my $value = $values->{$col};
    $self->{$col} = ref $value ? (${$value} eq 'true' ? 1 : 0) : $value;
  }
  return $self;
}

package FakePorts;
sub new { my ($class, @rows) = @_; return bless { rows => [@rows] }, $class; }
sub all { @{ $_[0]{rows} } }
sub reset { $_[0] }
sub single { my ($self, $cond) = @_; return (grep { $_->port eq $cond->{port} } $self->all)[0] }
sub get_column { $_[0] }
sub as_query { \['(SELECT port FROM device_port WHERE ip = ?)'] }

package FakeDevicePortRS;
sub search { my ($self, $where) = @_; return bless { where => $where }, ref $self }
sub single {
  my ($self, $cond) = @_;
  return (grep { $_->{owner} eq $cond->{ip} and $_->port eq $cond->{port} } @main::port_rows)[0];
}
sub update {
  my ($self, $set) = @_;
  my ($sql, @bind) = DBIx::Class::SQLMaker->new->update('device_port', $set, $self->{where});
  push @main::port_updates, { sql => $sql, bind => [@bind], set => $set };
  return 0;
}

package FakeTopologyRS;
sub search { $_[0] }
sub delete { 0 }
sub next { shift @{ $_[0]{links} } }

package FakeLink;
sub dev1 { $_[0]{dev1} } sub port1 { $_[0]{port1} }
sub dev2 { $_[0]{dev2} } sub port2 { $_[0]{port2} }

package FakePeer;
sub ip { $_[0]{ip} }
sub in_storage { 1 }
sub ports { $_[0]{ports} }

package FakeSchema;
# rolls back the row updates made inside a block that dies, as Netdisco's
# auto_savepoint makes a nested txn_do do
sub txn_do {
  my ($self, $code, @args) = @_;
  my $mark = scalar @main::row_updates;
  my @result = eval { $code->(@args) };
  if (my $error = $@) {
    foreach my $undo (reverse splice @main::row_updates, $mark) {
      my ($row, $old) = @{$undo}[3, 4];
      $row->{$_} = $old->{$_} for keys %$old;
    }
    die $error;
  }
  return @result;
}
sub resultset {
  my ($self, $name) = @_;
  return bless({}, 'FakeDevicePortRS') if $name eq 'DevicePort';
  return bless({ links => [ map { bless {%$_}, 'FakeLink' } @main::links ] }, 'FakeTopologyRS')
    if $name eq 'Topology';
  die "unexpected resultset $name";
}

package main;

our (@row_updates, @port_updates, @links, @warnings, @port_rows);

my %device_cols = (
  ip => '192.0.2.1', name => 'switch1', snmp_class => 'SNMP::Info::Layer2',
  custom_fields => '{}', snmp_ver => 2,
);

my %base_snmp = (
  has_topo   => 1,
  interfaces => { 1 => 'Gi1/1', 2 => 'Gi1/2', 3 => 'Gi1/3' },
  c_if       => { '1.1' => 1 },
  c_ip       => { '1.1' => '192.0.2.10' },
  c_port     => { '1.1' => 'Gi0/1' },
  c_id       => { '1.1' => 'peer1' },
  c_platform => { '1.1' => 'switch' },
  c_cap      => {},
);

sub outcome {
  my ($method, %more) = @_;
  return { method => $method, leaf => "MIB::$method", reason => 'timeout',
           rows => 1, walk => 'bulkwalk', complete => 0, %more };
}

sub run_neighbors {
  my (%args) = @_;
  delete @{ vars() }{qw/device_ports incomplete_walks queued/};
  @row_updates = @port_updates = @warnings = ();
  @links = @{ $args{links} || [] };

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{_column_data}{since_last_discover} = 0;

  my $ports = FakePorts->new(map { FakePortRow->new(owner => '192.0.2.1', port => $_,
    %{ $args{port_cols}{$_} || {} }) } 'Gi1/1', 'Gi1/2', 'Gi1/3', @{ $args{more_ports} || [] });
  my $peer = bless { ip => '192.0.2.20', ports => FakePorts->new(
    map { FakePortRow->new(owner => '192.0.2.20', port => $_, %{ $args{peer_cols}{$_} || {} }) }
      @{ $args{peer_ports} || ['Gi0/9'] }) }, 'FakePeer';
  @port_rows = ($ports->all, $peer->ports->all);
  vars->{'device_ports'} = $args{cached_ports} if $args{cached_ports};

  my $fake_snmp = FakeSNMP->new(%base_snmp, %{ $args{snmp} || {} });
  my $pkg = 'App::Netdisco::Worker::Plugin::Discover::Neighbors';

  no strict 'refs';
  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::DB::Result::Device::ports = sub { return $ports };
  local *{"${pkg}::schema"} = sub { return bless {}, 'FakeSchema' };
  local *{"${pkg}::warning"} = sub { push @warnings, @_ };
  local *{"${pkg}::acl_matches"} = sub { $args{disabled} and $_[1] eq 'skip_neighbors' };
  local *{"${pkg}::is_discoverable"} = sub { 1 };
  local *{"${pkg}::jq_insert"} = sub { 1 };
  local *{"${pkg}::get_device"} = sub {
    return $_[0] eq $device->ip ? $device : $_[0] eq $peer->ip ? $peer
      : bless { ip => $_[0] }, 'FakePeer';
  };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'discover::neighbors',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

sub status_messages { return join "\n", map { $_->log } @{ $_[0]->_statuslist } }
sub error_messages { return map { $_->log } grep { $_->status eq 'error' } @{ $_[0]->_statuslist } }

sub neighbor_clears { return grep { exists $_->{set}{remote_ip} } @port_updates }
sub manual_resets { return grep { not exists $_->{set}{remote_ip} } @port_updates }

sub discovered_writes {
  return map { $_->[1] } grep { $_->[0] eq '192.0.2.1' and exists $_->[2]{remote_type}
      and ${ $_->[2]{manual_topo} } eq q{false} }
    @row_updates;
}

my $manual_link = { dev1 => '192.0.2.1', port1 => 'Gi1/3', dev2 => '192.0.2.20', port2 => 'Gi0/9' };

subtest 'neighbors__neighbor_left__clears_that_port_only' => sub {
  my $job = run_neighbors();
  is_deeply [discovered_writes()], ['Gi1/1'], 'the reporting port is written';
  my @clears = neighbor_clears();
  is scalar @clears, 1, 'one clear statement';
  my $sql = $clears[0]{sql};
  like $sql, qr/^UPDATE device_port SET/;
  like $sql, qr/SET is_uplink = \?, remote_id = \?, remote_ip = \?, remote_port = \?, remote_type = \? WHERE/;
  ok +(exists $clears[0]{set}{is_uplink} and not defined $clears[0]{set}{is_uplink}),
    'is_uplink cleared to NULL, as the rebuild left it';
  unlike $sql, qr/SET.*manual_topo.*WHERE/, 'manual_topo not written';
  like $sql, qr/port NOT IN \( \? \)/, 'the written port is kept';
  like $sql, qr/ip = \?/;
  like $sql, qr/remote_ip IS NOT NULL OR remote_port IS NOT NULL OR remote_type IS NOT NULL OR remote_id IS NOT NULL OR is_uplink IS TRUE \)/,
    'only rows not already clear are written';
  is_deeply [ grep { defined } @{ $clears[0]{bind} } ], ['192.0.2.1', 'Gi1/1'],
    'device ip and kept port bound, the cleared values are NULL';
  like status_messages($job), qr/processed 1 neighbors/;
  is scalar @warnings, 0, 'no warning';
};

subtest 'neighbors__manual_topo_port__never_cleared_by_discovered_pass' => sub {
  run_neighbors(links => [$manual_link],
    snmp => { c_if => { '1.1' => 1, '3.1' => 3 },
              c_ip => { '1.1' => '192.0.2.10', '3.1' => '192.0.2.11' } });
  is_deeply [discovered_writes()], ['Gi1/1'], 'the manual port is not overwritten';
  my @clears = neighbor_clears();
  is scalar @clears, 1, 'one clear statement';
  like $clears[0]{sql}, qr/\(NOT manual_topo\)/, 'manual ports are excluded';
};

subtest 'neighbors__disabled__clears_all_ports_including_manual' => sub {
  my $job = run_neighbors(disabled => 1, links => [$manual_link]);
  my @clears = neighbor_clears();
  is scalar @clears, 1, 'one clear statement';
  my $sql = $clears[0]{sql};
  like $sql, qr/SET .*manual_topo = false.*WHERE/, 'manual_topo set false';
  unlike $sql, qr/NOT manual_topo/, 'manual ports are included';
  like $sql, qr/is_uplink IS TRUE OR manual_topo/, 'a manual row counts as not clear';
  unlike $sql, qr/port NOT IN/, 'no port is kept';
  is scalar(manual_resets()), 0, 'manual topology is not applied';
  is scalar @row_updates, 0, 'no port row written';
  like status_messages($job), qr/neighbor discovery is disabled/;
};

subtest 'neighbors__disabled_new_port__is_cleared_too' => sub {
  run_neighbors(disabled => 1, cached_ports => { 'Gi1/1' => FakePortRow->new(port => 'Gi1/1') });
  my @clears = neighbor_clears();
  is scalar @clears, 1, 'one clear statement';
  unlike $clears[0]{sql}, qr/\bport\b/, 'scoped by device, not by the port cache';
  is_deeply [ grep { defined } @{ $clears[0]{bind} } ], ['192.0.2.1'];
};

subtest 'neighbors__no_topo_protocols__clears_non_manual_ports' => sub {
  my $job = run_neighbors(links => [$manual_link], snmp => { has_topo => undef });
  is scalar(manual_resets()), 1, 'manual topology applied first';
  my @clears = neighbor_clears();
  is scalar @clears, 1, 'one clear statement';
  my $sql = $clears[0]{sql};
  like $sql, qr/\(NOT manual_topo\)/, 'manual links stay';
  unlike $sql, qr/SET .*manual_topo.*WHERE/, 'manual_topo not written';
  unlike $sql, qr/port NOT IN/, 'no port is kept';
  like status_messages($job), qr/processed 0 neighbors/;
};

subtest 'neighbors__incomplete_c_ip__writes_found_clears_nothing' => sub {
  my $job = run_neighbors(snmp => { fail_on_read => { c_ip => outcome('c_ip') } });
  is_deeply [discovered_writes()], ['Gi1/1'], 'the neighbor found is written';
  is scalar(neighbor_clears()), 0, 'nothing cleared';
  is scalar @warnings, 1, 'one warning';
  like $warnings[0], qr/\[192\.0\.2\.1\] neigh - .+incomplete SNMP walk: c_ip /;
  is scalar(error_messages($job)), 0, 'a cut-short walk does not error the job';
  like status_messages($job),
    qr/processed 1 neighbors; \[192\.0\.2\.1\] neigh - .+incomplete SNMP walk: c_ip /,
    'the job log shows clearing was skipped';
  ok !$job->is_cancelled, 'the guard never cancels';
};

for my $method (qw/c_if c_port c_id c_platform c_cap interfaces/) {
  subtest "neighbors__incomplete_${method}__clears_nothing" => sub {
    run_neighbors(snmp => { walk_status => { $method => outcome($method) } });
    is scalar(neighbor_clears()), 0, 'nothing cleared';
    like $warnings[0], qr/incomplete SNMP walk: \Q$method\E /;
  };
}

subtest 'neighbors__incomplete_has_topo__clears_nothing' => sub {
  run_neighbors(snmp => { has_topo => undef,
    fail_on_read => { has_topo => outcome('has_topo') } });
  is scalar(neighbor_clears()), 0, 'nothing cleared';
  is scalar @warnings, 1, 'one warning';
  like $warnings[0], qr/incomplete SNMP walk: has_topo /;
};

subtest 'neighbors__absent_walk__clears_nothing_and_errors_the_job' => sub {
  my $job = run_neighbors(snmp => { walk_status =>
    { c_id => outcome('c_id', reason => 'absent', complete => 1, rows => 0) } });
  is_deeply [discovered_writes()], ['Gi1/1'], 'the neighbor found is written';
  is scalar(neighbor_clears()), 0, 'nothing cleared';
  my @errors = error_messages($job);
  is scalar @errors, 1, 'one error status';
  like $errors[0], qr/neigh .+ netdisco-mibs/;
};

subtest 'neighbors__manual_topo_reset__updates_only_rows_that_change' => sub {
  run_neighbors(links => [$manual_link]);
  my @resets = manual_resets();
  is scalar @resets, 1, 'one reset statement';
  is_deeply [ keys %{ $resets[0]{set} } ], ['manual_topo'];
  like $resets[0]{sql}, qr/^UPDATE device_port SET manual_topo = false WHERE/;
  like $resets[0]{sql}, qr/WHERE .*\bmanual_topo\b/, 'only rows still manual';
  unlike $resets[0]{sql}, qr/NOT manual_topo/;
  like $resets[0]{sql}, qr/port NOT IN \( \? \)/, 'this run\'s manual link port is excluded';
  is_deeply $resets[0]{bind}, ['192.0.2.1', 'Gi1/3'];
  my ($manual) = grep { $_->[1] eq 'Gi1/3' } @row_updates;
  ok $manual, 'the manual link is applied';
  ok ${ $manual->[2]{manual_topo} } eq 'true', 'as manual topology';
  ok vars->{'device_ports'}{'Gi1/3'}->manual_topo, 'the refreshed cache sees it';
};

subtest 'neighbors__manual_topo_reset_no_links__resets_any_still_manual' => sub {
  run_neighbors();
  my @resets = manual_resets();
  is scalar @resets, 1, 'one reset statement';
  like $resets[0]{sql}, qr/WHERE .*\bmanual_topo\b/, 'only rows still manual';
  unlike $resets[0]{sql}, qr/\bport\b/, 'no port excluded';
  is_deeply $resets[0]{bind}, ['192.0.2.1'];
};

subtest 'neighbors__manual_link_peer_port_missing__left_port_reset' => sub {
  run_neighbors(links => [$manual_link], peer_ports => ['Gi0/8']);
  ok !(grep { $_->[1] eq 'Gi1/3' } @row_updates), 'the left update is rolled back';
  my @resets = manual_resets();
  is scalar @resets, 1, 'one reset statement';
  unlike $resets[0]{sql}, qr/\bport\b/, 'the left port is not excluded from the reset';
  is_deeply $resets[0]{bind}, ['192.0.2.1'];
};

subtest 'neighbors__aggregate_master__kept_and_stale_ids_cleared' => sub {
  run_neighbors(more_ports => ['Po1'],
    port_cols => { 'Gi1/1' => { slave_of => 'Po1' }, 'Po1' => { remote_type => 'old', remote_id => 'old' } },
    peer_ports => ['Gi0/1', 'Po9'], peer_cols => { 'Gi0/1' => { slave_of => 'Po9' } },
    snmp => { c_ip => { '1.1' => '192.0.2.20' } });
  my ($master) = grep { $_->[1] eq 'Po1' } @row_updates;
  ok $master, 'the master is written';
  is $master->[2]{remote_ip}, '192.0.2.20';
  is $master->[2]{remote_port}, 'Po9';
  ok +(exists $master->[2]{remote_type} and not defined $master->[2]{remote_type}), 'remote_type cleared';
  ok +(exists $master->[2]{remote_id} and not defined $master->[2]{remote_id}), 'remote_id cleared';
  my @clears = neighbor_clears();
  is scalar @clears, 1, 'one clear statement';
  like $clears[0]{sql}, qr/port NOT IN \( \?, \? \)/;
  is_deeply [ grep { defined } @{ $clears[0]{bind} } ], ['192.0.2.1', 'Gi1/1', 'Po1'],
    'the member and the master are kept';
};

done_testing;
