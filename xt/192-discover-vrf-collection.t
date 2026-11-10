#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::DB::Upsert ();
use App::Netdisco::Backend::Job;
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Worker::Plugin::Discover::Properties ();
use App::Netdisco::Worker::Plugin::Discover::Properties::Tags ();

use Try::Tiny;
use List::Util ();
use Dancer qw/:moose :script !pass/;

# The alias worker with store_vrfs on, run as in xt/167: SNMP and storage are
# stubbed and upsert and remove_unseen record their rows. The fake session
# answers a VRF's readers only in that VRF's context, so a read in the wrong
# context returns nothing, as SNMP::Info does.

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
config->{'enable_field_protection'} = 0;
config->{'enable_incomplete_walk_protection'} = 1;
config->{'ignore_deviceports'} = [];
config->{'ignore_private_nets'} = 0;
config->{'dns'}->{'no'} = ['0.0.0.0/0'];

our @events;

package FakeSNMP;
our $AUTOLOAD;
{ package NoopTagsSchema; sub resultset { return $_[0] } sub search { return $_[0] } sub update { return 0 } }

sub new {
  my ($class, %vals) = @_;
  return bless { walk_failures => [], context => '', contexts_asked => [], %vals }, $class;
}
sub walk_failures { $_[0]{walk_failures} }
# the latest outcome of a method, by the context it was walked in
sub walk_status { my ($self, $method) = @_; return $self->{walk_status_in}{ $self->{context} }{$method} }
sub snmp_ver { $_[0]{snmp_ver} || 2 }
sub snmp_comm { 'public' }
sub update {
  my ($self, %args) = @_;
  $self->{context} = exists $args{Context} ? $args{Context}
    : ($args{Community} =~ m/\@(.+)$/ ? $1 : '');
  push @{ $self->{contexts_asked} }, $self->{context};
  # a reconnect that fails after the session already moved
  die "update failed\n" if $self->{die_on_update_to}
    and $self->{context} eq $self->{die_on_update_to};
  return 1;
}

# the context SNMP::Info would expect the session in for this instance
sub _context_of {
  my ($self, $name) = @_;
  my $ctx = $self->{instances}{$name}{contexts}[0];
  return '' if not $ctx or ($ctx->{kind} || '') eq 'none';
  return $ctx->{id};
}
sub _in_default { return $_[0]{context} eq '' }

sub vrf_instances {
  my $self = shift;
  $self->{reads}{vrf_instances}++;
  return $self->_in_default ? $self->{instances} : undef;
}
sub vrf_instances_complete {
  my $self = shift;
  $self->{reads}{vrf_instances_complete}++;
  return $self->_in_default ? $self->{instances_complete} : undef;
}
sub interfaces {
  my $self = shift;
  # a cut-short walk records itself, as SNMP::Info's walk_failures does
  push @{ $self->{walk_failures} }, $self->{fail_interfaces_in}{ $self->{context} }
    if $self->{fail_interfaces_in}{ $self->{context} };
  return $self->{interfaces} if $self->_in_default;
  return $self->{context_interfaces}{ $self->{context} };
}
sub _vrf_answer {
  my ($self, $what, $name) = @_;
  push @{ $self->{vrf_reads}{$name} }, $what;
  return undef unless $self->{context} eq $self->_context_of($name);
  return $self->{vrf}{$name}{$what};
}
sub vrf_addresses { $_[0]->_vrf_answer('addresses', $_[1]) }
sub vrf_subnets { $_[0]->_vrf_answer('subnets', $_[1]) }
sub vrf_read_complete { $_[0]->_vrf_answer('complete', $_[1]) }

sub AUTOLOAD {
  my $self = shift;
  (my $method = $AUTOLOAD) =~ s/.*:://;
  return if $method eq 'DESTROY';
  $self->{reads}{$method}++;
  return $self->{$method};
}

package FakeRows;
sub new { my ($class, @rows) = @_; return bless { rows => [@rows] }, $class; }
sub reset { return $_[0] }
sub all { return @{ $_[0]->{rows}} }

package FakeLockedRow;
sub new { return bless {}, shift }
sub first { return $_[0] }

package FakeSchema;
sub txn_do {
  my ($self, $code) = @_;
  push @main::events, 'txn';
  my $result = $code->();
  push @main::events, 'commit';
  return $result;
}
sub resultset { my ($self, $name) = @_; return App::Netdisco::DB->resultset($name) }

package main;

my %device_cols = (
  ip => '192.0.2.1', uptime => 900, description => 'desc', name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', chassis_id => 'chassis1', contact => '',
  location => 'Room A', num_ports => 2, snmp_class => 'SNMP::Info::Layer2',
  snmp_engineid => '', custom_fields => '{}', snmp_ver => 2,
);

# %device_cols and %base_snmp are xt/167's fixtures, so a run with store_vrfs off
# and no VRF answers is the input xt/167 pins
my %base_snmp = (
  vtp_d_name => undef, vtp_d_mode => undef,
  description => 'desc', uptime => 900, name => 'switch1',
  layers => 2, mac => '00:00:00:00:00:01', vendor => 'cisco', os => 'ios', os_ver => '1.0',
  model => 'cat', serial => 'SN1', serial1 => 'chassis1', contact => '', location => 'Room A',
  ports => 2, class => 'SNMP::Info::Layer2', snmpEngineID => '', id => undef,
  load_uptime => 900,
  interfaces => { 1 => 'Gi1/1', 2 => 'Gi1/2' },
  i_type => { 1 => '6', 2 => '6' }, i_ignore => {},
  i_description => { 1 => 'Gi1/1', 2 => 'Gi1/2' },
  agg_ports => {}, i_subinterfaces => {},
  ip_index   => { '192.0.2.1' => 1, '198.51.100.7' => 2 },
  ip_table   => { '192.0.2.1' => '192.0.2.1', '198.51.100.7' => '198.51.100.7' },
  ip_netmask => { '192.0.2.1' => '255.255.255.0', '198.51.100.7' => '255.255.255.0' },
);

sub context_record { my $name = shift;
  return [{ kind => 'vrf', id => $name, v2c => "%s\@$name", v3 => $name }] }

sub instance {
  my ($name, %over) = @_;
  return {
    name => $name, kind => ($name eq 'default' ? 'default' : 'vrf'),
    description => undef, oper => 'up', rd => undef, rt_import => [], rt_export => [],
    l3_vni => undef, l3_isid => undef, listed_by => 'device', sources => {},
    contexts => ($name eq 'default' ? [{ kind => 'none' }] : context_record($name)),
    %over,
  };
}

sub address { my ($ifindex, $ip, $len) = @_;
  return ("$ifindex.$ip" => { ifindex => $ifindex, ip => $ip, prefix_len => $len,
    family => ($ip =~ m/:/ ? 'ipv6' : 'ipv4') }) }
sub subnet { my ($prefix, $len, $ifindex) = @_;
  return ("$prefix/$len" => { prefix => $prefix, len => $len, ifindex => $ifindex,
    family => ($prefix =~ m/:/ ? 'ipv6' : 'ipv4'), sources => ['address'] }) }

# default holds the polled address; red and blue hold one address between them
sub vrf_fixture {
  return (
    instances_complete => 1,
    instances => {
      default => instance('default'),
      red  => instance('red', rd => '64512:30', rt_import => ['64512:30'], rt_export => ['64512:31']),
      blue => instance('blue', rd => '<not set>'),
    },
    context_interfaces => { red => { 7 => 'Vlan7' }, blue => { 8 => 'Vlan8' } },
    vrf => {
      default => { complete => 1,
        addresses => { address(1, '192.0.2.1', 24), address(2, '198.51.100.7', 24) },
        subnets => { subnet('192.0.2.0', 24, 1), subnet('198.51.100.0', 24, 2) } },
      red => { complete => 1,
        addresses => { address(7, '10.40.0.1', 24),
                       address(7, '2001:0db8:0000:0000:0000:0000:0000:0001', 64) },
        subnets => { subnet('10.40.0.0', 24, 7),
                     subnet('2001:0db8:0000:0000:0000:0000:0000:0000', 64, 7) } },
      blue => { complete => 1,
        addresses => { address(8, '10.40.0.1', 24) },
        subnets => { subnet('10.40.0.0', 24, 8) } },
    },
  );
}

my (@upserts, @removals);
our $stored_rows = [];
our $stored_vrfs = [];
our @warnings;
our $recompute_dies = 0;
our @debugs;
our %remove_returns;
my $last_snmp;

sub with_settings {
  my ($code, %settings) = @_;
  my %saved = map { $_ => setting($_) } keys %settings;
  set($_ => $settings{$_}) for keys %settings;
  my @result = eval { $code->() };
  my $error = $@;
  set($_ => $saved{$_}) for keys %saved;
  die $error if $error;
  return @result;
}

sub run_discover {
  my (%snmp) = @_;
  delete @{ vars() }{qw/device_changed new_device device_ports hook_data timestamp incomplete_walks/};
  @upserts = @removals = @events = @warnings = @debugs = ();

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ %device_cols });
  $device->in_storage(1);
  $device->{'_column_data'}{'since_last_discover'} = 0;

  my $fake_snmp = FakeSNMP->new(%base_snmp, %snmp);
  $last_snmp = $fake_snmp;
  my $search = DBIx::Class::ResultSet->can('search');
  no warnings 'once';

  local *App::Netdisco::Transport::SNMP::reader_for = sub { return $fake_snmp };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::Tags::schema
    = sub { return bless {}, 'NoopTagsSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::schema
    = sub { return bless {}, 'FakeSchema' };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::recompute_l3_domains
    = sub { push @events, 'recompute'; die "lock timeout\n" if $recompute_dies; return 0 };
  # the real one asks the database about vrf_domains, manual rows and legacy keys (xt/213)
  local *App::Netdisco::Worker::Plugin::Discover::Properties::l3_domain_recompute_needed
    = sub { return $_[1] ? 1 : 0 };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::debug = sub { push @debugs, @_ };
  local *App::Netdisco::DB::Result::Device::ports = sub { return FakeRows->new };
  local *App::Netdisco::DB::Result::Device::device_ips = sub { return FakeRows->new(@$stored_rows) };
  local *DBIx::Class::ResultSet::search = sub {
    my ($rs) = @_;
    return FakeRows->new(@$stored_vrfs) if $rs->result_source->source_name eq 'DeviceVrf';
    return $search->(@_);
  };
  local *App::Netdisco::DB::Result::Device::vrfs = sub { return FakeRows->new(@$stored_vrfs) };
  local *App::Netdisco::Worker::Plugin::Discover::Properties::warning = sub { push @warnings, @_ };
  local *App::Netdisco::DB::Result::Device::update = sub { return $_[0] };
  local *App::Netdisco::DB::Result::Device::update_or_insert = sub { return $_[0] };
  local *App::Netdisco::DB::Upsert::upsert = sub {
    my ($rs, $rows) = @_;
    my $name = $rs->result_source->source_name;
    push @upserts, [ $name, $rows ];
    push @events, "upsert $name";
    return 0;
  };
  local *App::Netdisco::DB::Upsert::remove_unseen = sub {
    my ($rs, $scope, $seen) = @_;
    my $name = $rs->result_source->source_name;
    push @removals, [ $name, $scope, $seen ];
    push @events, "remove $name";
    return $remove_returns{$name} // 0;
  };
  local *App::Netdisco::DB::ResultSet::DevicePort::retire_ports = sub { return 0 };
  local *App::Netdisco::DB::ResultSet::Device::search = sub {
    my ($rs, $cond, $attrs) = @_;
    return ($attrs and $attrs->{for}) ? FakeLockedRow->new : $search->(@_);
  };

  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'discover::properties',
  });

  try { MyWorker->new()->run($job) }
  catch { $job->status('error'); $job->log("error running job: $_") };

  return $job;
}

sub run_with_vrfs {
  my (%snmp) = @_;
  my $settings = delete $snmp{settings} || {};
  return with_settings(sub { run_discover(vrf_fixture(), %snmp) }, store_vrfs => 1, %$settings);
}

sub upserted { my $source = shift; return map { @{ $_->[1] } } grep { $_->[0] eq $source } @upserts }
sub removals_of { my $source = shift; return grep { $_->[0] eq $source } @removals }
sub keyed { return join ' ', sort map { join '|', $_->{alias} // '', $_->{vrf} } @_ }
sub vrf_keys { return join ' ', sort map { $_->{vrf} } @_ }
sub nets_in { my $vrf = shift; return sort map { $_->{net} } grep { $_->{vrf} eq $vrf } upserted('Subnet') }

sub without_creation { return [ map { my %row = %$_; delete $row{creation}; \%row } @_ ] }

# today's path on xt/167's input, with no VRF methods answering
sub todays_writes {
  my %settings = @_;
  return {
    rows     => without_creation(upserted('DeviceIp')),
    seen     => [ map { $_->[2] } removals_of('DeviceIp') ],
    subnets  => [ sort map { "$_->{net} $_->{vrf}" } upserted('Subnet') ],
  };
}
my $todays = do { with_settings(sub { run_discover() }, store_vrfs => 0); todays_writes() };

subtest 'discover__switch_off__identical_rows_to_today' => sub {
  is_deeply [ map { $_->{alias} } @{ $todays->{rows} } ], [ '192.0.2.1', '198.51.100.7' ],
    'the expectation holds xt/167 aliases';
  with_settings(sub { run_discover(vrf_fixture()) }, store_vrfs => 0);
  is_deeply todays_writes(), $todays, 'rows, seen and subnets as today';
  ok !$last_snmp->{reads}{vrf_instances}, 'vrf_instances not read';
  ok !$last_snmp->{reads}{vrf_instances_complete}, 'vrf_instances_complete not read';
  is scalar(upserted('DeviceVrf')), 0, 'no device_vrf rows';
  # a device that stops being VRF-collected must not keep its VRFs and domains
  is_deeply [ map { [ @$_[1, 2] ] } removals_of('DeviceVrf') ], [ [ { ip => '192.0.2.1' }, [] ] ],
    'every device_vrf row of the device removed';
  ok !(grep { $_ eq 'recompute' } @events), 'no recompute when there was none to remove';
};

subtest 'discover__switch_off_with_stored_vrfs__device_vrf_cleared_then_recompute' => sub {
  local %remove_returns = (DeviceVrf => 2);
  with_settings(sub { run_discover(vrf_fixture()) }, store_vrfs => 0);
  is scalar(removals_of('DeviceVrf')), 1, 'device_vrf removed';
  my @order = grep { $_ eq 'remove DeviceVrf' or $_ eq 'recompute' } @events;
  is_deeply \@order, [ 'remove DeviceVrf', 'recompute' ], 'domains recomputed after the removal';
};

subtest 'discover__skip_vrf_devices__device_vrf_cleared' => sub {
  local %remove_returns = (DeviceVrf => 1);
  run_with_vrfs(settings => { skip_vrf_devices => ['192.0.2.1'] });
  is_deeply [ map { $_->[2] } removals_of('DeviceVrf') ], [ [] ], 'every device_vrf row removed';
  ok scalar(grep { $_ eq 'recompute' } @events), 'domains recomputed';
};

subtest 'discover__unsupported_class__identical_rows_to_today' => sub {
  run_with_vrfs(instances_complete => undef);
  is_deeply todays_writes(), $todays, 'rows, seen and subnets as with the switch off';
  ok !$last_snmp->{reads}{vrf_instances}, 'vrf_instances not read';
  is scalar(upserted('DeviceVrf')), 0, 'no device_vrf rows';
  # collection is still on: rows a CLI collector recorded are its own to retire
  is scalar(removals_of('DeviceVrf')), 0, 'no device_vrf removal';
  ok !(grep { $_ eq 'recompute' } @events), 'no recompute';
};

subtest 'discover__two_vrfs_same_address__two_device_ip_rows' => sub {
  run_with_vrfs();
  my @rows = upserted('DeviceIp');
  my ($red) = grep { $_->{alias} eq '10.40.0.1' and $_->{vrf} eq 'red' } @rows;
  my ($blue) = grep { $_->{alias} eq '10.40.0.1' and $_->{vrf} eq 'blue' } @rows;
  ok $red && $blue, 'one row in each VRF';
  is $red->{port}, 'Vlan7', 'red port from its own context';
  is $blue->{port}, 'Vlan8', 'blue port from its own context';
  is $red->{subnet}, '10.40.0.0/24';
  is $red->{ip}, '192.0.2.1';
  is ${ $red->{creation} }, 'LOCALTIMESTAMP';
  is_deeply [ sort keys %$red ], [qw/alias creation dns ip port subnet vrf/], 'same keys as today';
  my ($v6) = grep { $_->{alias} =~ m/^2001/ } @rows;
  is $v6->{alias}, '2001:db8:0:0:0:0:0:1', 'IPv6 spelled as today';
  is $v6->{subnet}, '2001:db8:0:0:0:0:0:0/64';
  my ($polled) = grep { $_->{alias} eq '192.0.2.1' } @rows;
  is $polled->{vrf}, '', 'default table stored as empty vrf';
  is $polled->{port}, 'Gi1/1';

  my @removed = removals_of('DeviceIp');
  is scalar @removed, 1, 'one removal';
  is_deeply $removed[0][1], { ip => '192.0.2.1' }, 'scoped by device';
  is keyed(@{ $removed[0][2] }), keyed(@rows), 'every VRF row is seen';

  is_deeply [ nets_in('red') ], [ '10.40.0.0/24', '2001:db8:0:0:0:0:0:0/64' ], 'red subnets';
  is_deeply [ nets_in('blue') ], [ '10.40.0.0/24' ], 'blue subnet';
  is_deeply [ nets_in('') ], [ '192.0.2.0/24', '198.51.100.0/24' ], 'default subnets';
  my ($net) = upserted('Subnet');
  is $net->{router_last}, '192.0.2.1', 'subnets carry the router';

  is_deeply $last_snmp->{contexts_asked}, [ 'blue', 'red', '' ],
    'default read without a switch, then names sorted, then one restore';
  is $last_snmp->{context}, '', 'session back in the default context';
};

subtest 'discover__default_instance__stored_as_empty_vrf_in_device_vrf' => sub {
  run_with_vrfs();
  my %row = map { ($_->{vrf} => $_) } upserted('DeviceVrf');
  is vrf_keys(values %row), ' blue red', 'one row per instance, default as empty';
  my $default = $row{''};
  is $default->{ip}, '192.0.2.1';
  is $default->{kind}, 'default';
  ok !defined $default->{rd}, 'no rd';
  is_deeply $default->{rt_import}, [], 'no import targets';
  is $default->{complete}, 1, 'complete';
  is ref $default->{last_discover}, 'SCALAR', 'last_discover is the worker timestamp';
  is_deeply [ sort keys %$default ],
    [qw/complete ip kind l3_isid last_discover listed_by rd rt_export rt_import vrf/], 'columns';
  is $row{red}{rd}, '64512:30', 'red rd';
  is_deeply $row{red}{rt_import}, ['64512:30'];
  is_deeply $row{red}{rt_export}, ['64512:31'];
  is $row{red}{listed_by}, 'device';
  ok !defined $row{blue}{rd}, 'unset rd sentinel stored as NULL';

  my @removed = removals_of('DeviceVrf');
  is scalar @removed, 1, 'one device_vrf removal';
  is_deeply $removed[0][1], { ip => '192.0.2.1' };
  is vrf_keys(@{ $removed[0][2] }), ' blue red', 'every instance seen';
};

subtest 'discover__incomplete_vrf__its_stored_rows_kept_others_refreshed' => sub {
  local $stored_rows = [
    { alias => '10.40.0.1', vrf => 'blue' }, { alias => '10.99.0.1', vrf => 'blue' },
    { alias => '203.0.113.9', vrf => 'red' }, { alias => '203.0.113.10', vrf => '' },
  ];
  my %fixture = vrf_fixture();
  $fixture{vrf}{blue}{complete} = 0;
  run_with_vrfs(vrf => $fixture{vrf});

  my @rows = upserted('DeviceIp');
  ok !(grep { $_->{vrf} eq 'blue' } @rows), 'no blue rows written from a short walk';
  ok scalar(grep { $_->{vrf} eq 'red' } @rows), 'red rows written';
  my @seen = @{ (removals_of('DeviceIp'))[0][2] };
  is keyed(grep { $_->{vrf} eq 'blue' } @seen), '10.40.0.1|blue 10.99.0.1|blue',
    'stored blue rows passed as seen';
  ok !(grep { $_->{alias} eq '203.0.113.9' } @seen), 'stale red row not seen, so removed';
  ok !(grep { $_->{alias} eq '203.0.113.10' } @seen), 'stale default row not seen, so removed';
  is_deeply [ nets_in('blue') ], [], 'no blue subnets';
  is_deeply [ nets_in('red') ], [ '10.40.0.0/24', '2001:db8:0:0:0:0:0:0/64' ], 'red subnets refreshed';
  my ($blue) = grep { $_->{vrf} eq 'blue' } upserted('DeviceVrf');
  is $blue->{complete}, 0, 'blue recorded as incomplete';
  my ($red) = grep { $_->{vrf} eq 'red' } upserted('DeviceVrf');
  is $red->{complete}, 1, 'red recorded as complete';
};

subtest 'discover__v2c_without_template__vrf_marked_incomplete_not_read' => sub {
  local $stored_rows = [ { alias => '10.40.0.1', vrf => 'blue' } ];
  my %fixture = vrf_fixture();
  $fixture{instances}{blue}{contexts} = [{ kind => 'vrf', id => 'blue', v2c => undef, v3 => 'blue' }];
  run_with_vrfs(instances => $fixture{instances});

  ok !$last_snmp->{vrf_reads}{blue}, 'blue readers never called';
  ok !(grep { $_ eq 'blue' } @{ $last_snmp->{contexts_asked} }), 'never switched to blue';
  my ($blue) = grep { $_->{vrf} eq 'blue' } upserted('DeviceVrf');
  ok $blue, 'blue still listed in device_vrf';
  is $blue->{complete}, 0, 'blue recorded as incomplete';
  ok !(grep { $_->{vrf} eq 'blue' } upserted('DeviceIp')), 'no blue rows written';
  my @seen = @{ (removals_of('DeviceIp'))[0][2] };
  is keyed(grep { $_->{vrf} eq 'blue' } @seen), '10.40.0.1|blue', 'stored blue row kept';
  is_deeply [ nets_in('blue') ], [], 'no blue subnets';
};

subtest 'discover__management_vrf_only_address__device_keeps_canonical_ip' => sub {
  my %fixture = vrf_fixture();
  $fixture{instances}{MGMT} = instance('MGMT');
  $fixture{context_interfaces}{MGMT} = { 9 => 'Management1' };
  $fixture{vrf}{MGMT} = { complete => 1,
    addresses => { address(9, '192.0.2.1', 24) }, subnets => { subnet('192.0.2.0', 24, 9) } };
  $fixture{vrf}{default}{addresses} = { address(2, '198.51.100.7', 24) };
  $fixture{vrf}{default}{subnets} = { subnet('198.51.100.0', 24, 2) };
  run_with_vrfs(%fixture);

  my @rows = upserted('DeviceIp');
  my @polled = grep { $_->{alias} eq '192.0.2.1' } @rows;
  is scalar @polled, 1, 'one row for the polled address';
  is $polled[0]{vrf}, 'MGMT', 'in the management VRF, no fake default row';
  is $polled[0]{port}, 'Management1';
  is_deeply [ List::Util::uniq map { $_->{ip} } @rows ], [ '192.0.2.1' ], 'device keeps its address';
  is_deeply [ map { $_->{alias} } @{ vars->{'hook_data'}{'device_ips'} } ],
    [ map { $_->{alias} } @rows ], 'hook payload holds the rows written';
};

subtest 'discover__polled_address_in_no_vrf__fake_default_row' => sub {
  my %fixture = vrf_fixture();
  $fixture{vrf}{default}{addresses} = { address(2, '198.51.100.7', 24) };
  run_with_vrfs(vrf => $fixture{vrf});
  my @polled = grep { $_->{alias} eq '192.0.2.1' } upserted('DeviceIp');
  is scalar @polled, 1, 'one row';
  is $polled[0]{vrf}, '', 'in the default table, as today';
  ok !defined $polled[0]{port}, 'no port';
};

subtest 'discover__polled_address_kept_in_incomplete_vrf__no_fake_default_row' => sub {
  local $stored_rows = [ { alias => '192.0.2.1', vrf => 'blue' } ];
  my %fixture = vrf_fixture();
  $fixture{vrf}{default}{addresses} = { address(2, '198.51.100.7', 24) };
  $fixture{vrf}{blue}{complete} = 0;
  run_with_vrfs(vrf => $fixture{vrf});
  ok !(grep { $_->{alias} eq '192.0.2.1' } upserted('DeviceIp')), 'no row written for it';
  my @seen = grep { $_->{alias} eq '192.0.2.1' } @{ (removals_of('DeviceIp'))[0][2] };
  is keyed(@seen), '192.0.2.1|blue', 'its stored row stands';
};

subtest 'discover__skipped_vrf__absent_from_device_ip_and_device_vrf' => sub {
  local $stored_rows = [ { alias => '10.40.0.1', vrf => 'blue' } ];
  local $stored_vrfs = [ { vrf => 'blue' }, { vrf => 'red' }, { vrf => '' } ];
  run_with_vrfs(settings => { vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:blue' } });

  ok !$last_snmp->{vrf_reads}{blue}, 'blue readers never called';
  ok !(grep { $_ eq 'blue' } @{ $last_snmp->{contexts_asked} }), 'never switched to blue';
  ok !(grep { $_->{vrf} eq 'blue' } upserted('DeviceIp')), 'no blue device_ip rows';
  ok !(grep { $_->{vrf} eq 'blue' } @{ (removals_of('DeviceIp'))[0][2] }), 'stored blue rows not seen';
  ok !(grep { $_->{vrf} eq 'blue' } upserted('DeviceVrf')), 'no blue device_vrf row';
  ok !(grep { $_->{vrf} eq 'blue' } @{ (removals_of('DeviceVrf'))[0][2] }), 'blue device_vrf not seen';
  is_deeply [ nets_in('blue') ], [], 'no blue subnets';
};

subtest 'discover__vrf_recorded_by_the_cli__kept' => sub {
  # SNMP::Info does not list it; CLI arpnip recorded it (record_cli_vrfs)
  local $stored_vrfs = [ { vrf => 'management', listed_by => 'cli' }, { vrf => 'old', listed_by => 'snmp' },
                         { vrf => 'red' }, { vrf => '' } ];
  run_with_vrfs();
  my @seen = map { $_->{vrf} } @{ (removals_of('DeviceVrf'))[0][2] };
  ok((grep { $_ eq 'management' } @seen), 'the CLI-recorded VRF is seen, so kept');
  ok(!(grep { $_ eq 'old' } @seen), 'a VRF SNMP no longer lists is not, so removed');
};

subtest 'discover__short_instance_list__unlisted_vrf_rows_kept' => sub {
  local $stored_rows = [
    { alias => '10.77.0.1', vrf => 'green' }, { alias => '10.40.0.1', vrf => 'blue' },
    { alias => '203.0.113.9', vrf => 'red' },
  ];
  local $stored_vrfs = [ { vrf => 'green' }, { vrf => 'blue' }, { vrf => 'red' }, { vrf => '' } ];
  my %fixture = vrf_fixture();
  delete $fixture{instances}{blue};
  run_with_vrfs(instances => $fixture{instances}, instances_complete => 0,
    settings => { vrf_no_devicevrfs => { 'group:__ANY__' => 'vrf:blue' } });

  my @seen = @{ (removals_of('DeviceIp'))[0][2] };
  is keyed(grep { $_->{vrf} eq 'green' } @seen), '10.77.0.1|green', 'unlisted VRF rows kept';
  ok !(grep { $_->{vrf} eq 'blue' } @seen), 'unlisted but skipped VRF rows removed';
  ok !(grep { $_->{alias} eq '203.0.113.9' } @seen), 'listed VRF still refreshed';
  ok !(grep { $_->{vrf} eq 'green' } upserted('DeviceIp')), 'nothing written for green';
  ok !(grep { $_->{vrf} eq 'green' } upserted('DeviceVrf')), 'no green device_vrf upsert';
  is vrf_keys(@{ (removals_of('DeviceVrf'))[0][2] }), ' green red', 'green device_vrf row kept';
  is_deeply [ nets_in('green') ], [], 'no green subnets';
};

subtest 'discover__complete_instance_list__unlisted_vrf_rows_removed' => sub {
  local $stored_rows = [ { alias => '10.77.0.1', vrf => 'green' } ];
  local $stored_vrfs = [ { vrf => 'green' } ];
  run_with_vrfs();
  ok !(grep { $_->{vrf} eq 'green' } @{ (removals_of('DeviceIp'))[0][2] }), 'green rows not seen';
  ok !(grep { $_->{vrf} eq 'green' } @{ (removals_of('DeviceVrf'))[0][2] }), 'green instance not seen';
};

subtest 'discover__recompute__called_once_after_commit' => sub {
  run_with_vrfs();
  my @recomputes = grep { $_ eq 'recompute' } @events;
  is scalar @recomputes, 1, 'once for two named VRFs';
  my ($recompute) = grep { $events[$_] eq 'recompute' } 0 .. $#events;
  is $events[$recompute - 1], 'commit', 'right after the transaction commits';
  my ($txn) = grep { $events[$_] eq 'txn' } reverse 0 .. $recompute;
  ok scalar(grep { $_ eq 'upsert DeviceVrf' } @events[ $txn .. $recompute ]),
    'device_vrf written inside that transaction';
  ok scalar(grep { $_ eq 'upsert DeviceIp' } @events[ $txn .. $recompute ]),
    'device_ip written inside that transaction';
};

sub attribution { my ($instances, $contexts) = @_;
  return { map { ($_ => ($_ eq 'default' ? $instances->{$_}
    : { %{ $instances->{$_} }, contexts => $contexts })) } keys %$instances } }

subtest 'discover__attribution_mode_vrfs__no_update_calls' => sub {
  my %fixture = vrf_fixture();
  run_with_vrfs(instances => attribution($fixture{instances}, [{ kind => 'none' }]));
  is_deeply $last_snmp->{contexts_asked}, [], 'no update() at all';
  my @rows = upserted('DeviceIp');
  ok scalar(grep { $_->{vrf} eq 'red' } @rows), 'red read in the default context';
  ok scalar(grep { $_->{vrf} eq 'blue' } @rows), 'blue read in the default context';
  is_deeply [ sort map { "$_->{vrf}=$_->{complete}" } upserted('DeviceVrf') ],
    [ '=1', 'blue=1', 'red=1' ], 'every instance complete';
};

# SNMP::Info gives an empty contexts list for a context-mode VRF that no
# context serves; attribution mode gives [{ kind => 'none' }]
subtest 'discover__empty_contexts__read_incomplete_rows_kept_without_update' => sub {
  my %fixture = vrf_fixture();
  local $stored_rows = [ { alias => '10.40.0.1', vrf => 'red' } ];
  run_with_vrfs(instances => attribution($fixture{instances}, []));
  is_deeply $last_snmp->{contexts_asked}, [], 'no update() at all';
  ok !$last_snmp->{vrf_reads}{red}, 'red never read';
  ok !$last_snmp->{vrf_reads}{blue}, 'blue never read';
  ok !(grep { $_->{vrf} eq 'red' } upserted('DeviceIp')), 'no red rows written';
  my @seen = @{ (removals_of('DeviceIp'))[0][2] };
  is keyed(grep { $_->{vrf} eq 'red' } @seen), '10.40.0.1|red', 'stored red row kept';
  is_deeply [ sort map { "$_->{vrf}=$_->{complete}" } upserted('DeviceVrf') ],
    [ '=1', 'blue=0', 'red=0' ], 'both recorded as incomplete';
};

subtest 'discover__no_contexts_key__read_in_default_without_update' => sub {
  my %fixture = vrf_fixture();
  delete $fixture{instances}{red}{contexts};
  run_with_vrfs(instances => $fixture{instances});
  is_deeply $last_snmp->{contexts_asked}, [ 'blue', '' ], 'only blue switched to';
  ok scalar(grep { $_->{vrf} eq 'red' } upserted('DeviceIp')), 'red read in place';
};

subtest 'discover__mixed_modes__in_place_reads_first_then_one_switch_and_restore' => sub {
  my %fixture = vrf_fixture();
  $fixture{instances}{red}{contexts} = [{ kind => 'none' }];
  run_with_vrfs(instances => $fixture{instances});
  is_deeply $last_snmp->{contexts_asked}, [ 'blue', '' ], 'blue switched to, then restored';
  ok scalar(grep { $_->{vrf} eq 'red' } upserted('DeviceIp')), 'red read in place';
  ok scalar(grep { $_->{vrf} eq 'blue' } upserted('DeviceIp')), 'blue read in its context';
};

subtest 'discover__short_interfaces_walk__vrf_read_kept' => sub {
  local $stored_rows = [ { alias => '10.40.0.1', vrf => 'red' } ];
  run_with_vrfs(fail_interfaces_in => { red => {
    method => 'interfaces', leaf => 'IF-MIB::ifDescr', reason => 'timeout',
    rows => 1, walk => 'bulkwalk', complete => 0, context => 'red' } });
  ok !(grep { $_->{vrf} eq 'red' } upserted('DeviceIp')), 'no red rows written';
  my @seen = @{ (removals_of('DeviceIp'))[0][2] };
  is keyed(grep { $_->{vrf} eq 'red' } @seen), '10.40.0.1|red', 'stored red row kept';
  is_deeply [ nets_in('red') ], [], 'no red subnets';
  my %complete = map { ($_->{vrf} => $_->{complete}) } upserted('DeviceVrf');
  is $complete{red}, 0, 'red recorded as incomplete';
  is $complete{blue}, 1, 'blue unaffected';
  is $complete{''}, 1, 'default unaffected';
};

subtest 'discover__interfaces_walk_recorded_incomplete__vrf_read_kept' => sub {
  local $stored_rows = [ { alias => '10.40.0.1', vrf => 'red' } ];
  # recorded by walk_status alone, not walk_failures, so only the interfaces
  # method check sees it
  run_with_vrfs(walk_status_in => { red => { interfaces => {
    method => 'interfaces', leaf => 'IF-MIB::ifDescr', reason => 'timeout',
    rows => 1, walk => 'bulkwalk', complete => 0, context => 'red' } } });
  ok !(grep { $_->{vrf} eq 'red' } upserted('DeviceIp')), 'no red rows written';
  my %complete = map { ($_->{vrf} => $_->{complete}) } upserted('DeviceVrf');
  is $complete{red}, 0, 'red recorded as incomplete';
  is $complete{blue}, 1, 'blue unaffected';
  is $complete{''}, 1, 'default unaffected';
};

subtest 'discover__recompute_fails__warns_and_discover_succeeds' => sub {
  local $recompute_dies = 1;
  my ($job) = run_with_vrfs();
  isnt $job->status, 'error', 'job not failed';
  ok scalar(upserted('DeviceVrf')), 'rows were written';
  is scalar(grep { m/L3 domain recompute failed.*lock timeout/ } @warnings), 1, 'one warning';
};

subtest 'discover__vrf_path__no_stored_rows__recomputes_each_time' => sub {
  run_with_vrfs();
  is scalar(grep { $_ eq 'recompute' } @events), 1, 'first discover recomputes';
  run_with_vrfs();
  is scalar(grep { $_ eq 'recompute' } @events), 1, 'so does one whose VRFs are all new again';
};

# xt/213 covers the other reasons to recompute; here only the device's evidence
sub stored_like_fixture {
  my %over = @_;
  return [
    { vrf => '', rt_import => [], rt_export => [], l3_isid => undef },
    { vrf => 'red', rt_import => ['64512:30'], rt_export => ['64512:31'], l3_isid => undef },
    { vrf => 'blue', rt_import => [], rt_export => [], l3_isid => undef },
    map { $over{extra} ? { vrf => $_, rt_import => [], rt_export => [], l3_isid => undef } : () } 'green',
  ];
}

subtest 'discover__unchanged_vrfs__no_recompute' => sub {
  local $stored_vrfs = stored_like_fixture();
  run_with_vrfs();
  ok scalar(upserted('DeviceVrf')), 'rows still written';
  ok !(grep { $_ eq 'recompute' } @events), 'no recompute';
  is scalar(grep { m/\[192\.0\.2\.1\].*recompute skipped/ } @debugs), 1, 'one debug line names the device';
};

subtest 'discover__rt_order_only_changed__no_recompute' => sub {
  my $fixture = { vrf_fixture() };
  $fixture->{instances}{red}{rt_import} = [ '64512:9', '64512:30', '64512:30', '' ];
  local $stored_vrfs = stored_like_fixture();
  $stored_vrfs->[1]{rt_import} = [ '64512:30', '64512:9' ];
  with_settings(sub { run_discover(%$fixture) }, store_vrfs => 1);
  ok !(grep { $_ eq 'recompute' } @events), 'same set in another order, no recompute';
};

subtest 'discover__rt_member_changed__recompute' => sub {
  local $stored_vrfs = stored_like_fixture();
  $stored_vrfs->[1]{rt_import} = ['64512:99'];
  run_with_vrfs();
  is scalar(grep { $_ eq 'recompute' } @events), 1, 'recomputed';
};

subtest 'discover__isid_changed__recompute' => sub {
  local $stored_vrfs = stored_like_fixture();
  $stored_vrfs->[2]{l3_isid} = 4100;
  run_with_vrfs();
  is scalar(grep { $_ eq 'recompute' } @events), 1, 'recomputed';
};

subtest 'discover__vrf_removed__recompute' => sub {
  local $stored_vrfs = stored_like_fixture(extra => 1);
  run_with_vrfs();
  ok !(grep { $_->{vrf} eq 'green' } @{ (removals_of('DeviceVrf'))[0][2] }), 'green removed';
  is scalar(grep { $_ eq 'recompute' } @events), 1, 'recomputed';
};

subtest 'discover__vrf_added__recompute' => sub {
  local $stored_vrfs = stored_like_fixture();
  splice @$stored_vrfs, 2, 1;
  run_with_vrfs();
  is scalar(grep { $_ eq 'recompute' } @events), 1, 'recomputed';
};

subtest 'discover__switch_dies__default_context_restored' => sub {
  my ($job) = run_with_vrfs(die_on_update_to => 'blue');
  is $job->status, 'error', 'the job reports the failure';
  is_deeply $last_snmp->{contexts_asked}, [ 'blue', '' ], 'the guard restored after the failed switch';
  is $last_snmp->{context}, '', 'session back in the default context';
};

# SNMP::Info's error() returns whatever error is pending since it was last
# read, so a VRF read that set none must not log one left by an earlier call
{ package ErrorPendingSnmp;
  sub new { my ($class, $pending) = @_; return bless { error => $pending }, $class }
  sub error { my $self = shift; my $error = $self->{error}; $self->{error} = undef; return $error }
  sub vrf_read_complete { return 0 } }
{ package ErrorLogDevice; sub ip { '192.0.2.1' } }

sub incomplete_read_log {
  my ($pending, $read_sets) = @_;
  my $snmp = ErrorPendingSnmp->new($pending);
  my @logged;
  local *App::Netdisco::Util::VRF::debug = sub { push @logged, @_ };
  App::Netdisco::Util::VRF::each_vrf_instance(bless({}, 'ErrorLogDevice'), $snmp,
    { default => { contexts => [] } },
    sub { $snmp->{error} = $read_sets if defined $read_sets; return {} });
  return join "\n", grep { /read incomplete/ } @logged;
}

subtest 'each_vrf_instance__incomplete_read_with_stale_earlier_error__log_omits_stale_error' => sub {
  my $log = incomplete_read_log('_global(serial1) NOSUCHOBJECT', undef);
  like $log, qr/VRF default read incomplete, keeping its rows$/, 'logged with no error appended';
  unlike $log, qr/NOSUCHOBJECT/, 'the earlier call\'s error is not reported';
};

subtest 'each_vrf_instance__incomplete_read_that_set_an_error__log_includes_it' => sub {
  my $log = incomplete_read_log('_global(serial1) NOSUCHOBJECT', 'Timeout on vrf walk');
  like $log, qr/VRF default read incomplete, keeping its rows: Timeout on vrf walk$/, 'the read\'s own error is appended';
};

# the address and subnet filters of the VRF path, as the flat path applies
# them; the /32 alias subnet is stored as master's flat path stores one
subtest 'discover__vrf_path_unusable_and_ignored_entries__left_out' => sub {
  my %fixture = vrf_fixture();
  $fixture{instances}{red} = instance('red', rd => undef);
  delete @{ $fixture{instances}{red} }{qw/rt_import rt_export/};
  $fixture{context_interfaces} = { red => undef, blue => { 8 => 'Vlan8' } };
  $fixture{vrf}{red}{addresses} = {
    address(7, '10.40.0.1', 24),
    address(7, '10.42.0.1', 32),
    address(7, '0.0.0.0', 8),
    address(7, '0:0:0:0:0:0:0:0', 64),
    address(7, '127.0.0.5', 8),
    address(7, 'fe80:0000:0000:0000:0000:0000:0000:0001', 64),
    'x.bogus'  => { ifindex => 7, ip => '10.0.0.256', prefix_len => 24, family => 'ipv4' },
    'x.noip'   => { ifindex => 7, ip => undef, family => 'ipv4' },
    'x.noport' => { ip => '10.43.0.1', family => 'ipv4' },
  };
  $fixture{vrf}{red}{subnets} = {
    subnet('10.40.0.0', 24, 7),
    subnet('127.0.0.0', 8, 7),
    subnet('fe80:0000:0000:0000:0000:0000:0000:0000', 64, 7),
    'x.nolen'  => { prefix => '10.44.0.0' },
    'x.noprefix' => { len => 24 },
    'x.bogus'  => { prefix => 'zz::zz::zz', len => 24 },
  };
  my ($job) = with_settings(sub { run_discover(%fixture, interfaces => undef) },
    store_vrfs => 1, ignore_private_nets => 0);
  is $job->status, 'done', 'discover finished';
  my @red = grep { $_->{vrf} eq 'red' } upserted('DeviceIp');
  is_deeply [ sort map { $_->{alias} } @red ], [ '10.40.0.1', '10.42.0.1', '10.43.0.1' ],
    'unspecified, loopback, link-local and unparsable addresses left out';
  my ($host) = grep { $_->{alias} eq '10.42.0.1' } @red;
  is $host->{subnet}, '10.42.0.1/32', 'a /32 address keeps its /32 subnet, as on master';
  my ($bare) = grep { $_->{alias} eq '10.43.0.1' } @red;
  is $bare->{subnet}, undef, 'no prefix length, no subnet';
  is $bare->{port}, undef, 'no ifindex, no port';
  my ($polled) = grep { $_->{alias} eq '192.0.2.1' } upserted('DeviceIp');
  is $polled->{port}, undef, 'no default interfaces, no default port';
  is_deeply [ nets_in('red') ], [ '10.40.0.0/24' ], 'only the usable red subnet stored';
  my ($red_vrf) = grep { $_->{vrf} eq 'red' } upserted('DeviceVrf');
  is_deeply [ @$red_vrf{qw/rd rt_import rt_export/} ], [ undef, [], [] ], 'absent RD and RT lists stored empty';

  %{ $fixture{vrf}{red}{addresses} } = (%{ $fixture{vrf}{red}{addresses} }, address(7, '203.0.113.1', 24));
  ($job) = with_settings(sub { run_discover(%fixture) }, store_vrfs => 1, ignore_private_nets => 1);
  is $job->status, 'done', 'discover with ignore_private_nets finished';
  is_deeply [ map { $_->{alias} } grep { $_->{vrf} eq 'red' } upserted('DeviceIp') ], [ '203.0.113.1' ],
    'ignore_private_nets drops the RFC 1918 aliases, keeps the public one';
  is_deeply [ nets_in('red') ], [], 'and the RFC 1918 subnet';
};

done_testing;
