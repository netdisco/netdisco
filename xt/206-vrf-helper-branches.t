#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once'; # local *glob = sub {} overrides below are single-use by design

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Util::VRF qw/vrf_skip_test netdisco_vrf vrf_instances_for/;
use App::Netdisco::Util::SNMP 'snmp_vrf_context';
use App::Netdisco::Util::L3Domain 'label_rows_by_domain';
use App::Netdisco::Util::PostgresFloor ();
use App::Netdisco::Util::Device ();
use App::Netdisco::DB::Deploy ();
use App::Netdisco::Transport::SSH ();
use App::Netdisco::SSHCollector::Platform::NXOS;
use App::Netdisco::SSHCollector::Platform::IOSXE;
use App::Netdisco::SSHCollector::Platform::IOSXR;
use App::Netdisco::SSHCollector::Platform::EOS;
use App::Netdisco::SSHCollector::Platform::VOSS;
use App::Netdisco::Worker::Plugin::Arpnip::Nodes ();
use App::Netdisco::Worker::Plugin::Arpnip::Subnets ();
use Test::Netdisco::FakeSSH;

use Dancer qw/:moose :script !pass/;

# Branches of the VRF helpers that the worker and collector tests do not
# reach: malformed or absent values, and the fallbacks for them. Each helper
# is called directly, with no database and no device.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => '192.0.2.1' });

sub with_settings {
  my ($code, %settings) = @_;
  my %saved = map { $_ => setting($_) } keys %settings;
  set($_ => $settings{$_}) for keys %settings;
  my @result = eval { $code->() };
  my $error = $@;
  set($_ => $saved{$_}) for keys %saved;
  die $error if $error;
  return wantarray ? @result : $result[0];
}

# an Expect stand-in serving one FakeSSH fixture, past the login prompt as
# the session openers leave it
sub fake_expect {
  my $text = shift;
  my $ssh = Test::Netdisco::FakeSSH->new(text => $text);
  my $exp = Test::Netdisco::FakeSSH::Expect->new($ssh);
  $exp->{buffer} = '';
  return ($exp, $ssh);
}

subtest 'vrf_skip_test__default_table_names_and_scalar_setting__not_skipped' => sub {
  with_settings(sub {
    my $skipped = vrf_skip_test($device);
    is $skipped->(undef), 0, 'undef name';
    is $skipped->(''), 0, 'empty name';
    is $skipped->('default'), 0, 'default';
    is $skipped->('red'), 0, 'scalar setting never matches';
  }, vrf_no_devicevrfs => '192.0.2.1:red');
};

subtest 'netdisco_vrf__undef__undef' => sub {
  is netdisco_vrf(undef), undef, 'undef stays undef';
  is netdisco_vrf('default'), '', 'default is the empty name';
  is netdisco_vrf('Default'), 'Default', 'only the exact name';
};

subtest 'vrf_instances_for__supported_class_without_instances__empty_hash' => sub {
  my $snmp = bless {}, 'NoInstancesSNMP';
  { package NoInstancesSNMP; sub vrf_instances_complete { 0 } sub vrf_instances { undef } }
  my $got = with_settings(sub { vrf_instances_for($device, $snmp) }, store_vrfs => 1);
  is_deeply $got, {}, 'no instances, not undef';
};

{
  package ContextSNMP;
  sub new { bless { updates => [] }, shift }
  sub snmp_ver { 2 }
  sub snmp_comm { 'public' }
  sub class { 'SNMP::Info::Layer3' }
  sub update { my ($self, %args) = @_; push @{ $self->{updates} }, \%args; return 1 }
}

subtest 'snmp_vrf_context__context_without_kind_or_name__switched_or_refused' => sub {
  my $snmp = ContextSNMP->new;
  is snmp_vrf_context($snmp, $device, { contexts => [{ v2c => '%s@red' }] }), 1,
    'a context with no kind and no instance name is switched to';
  is_deeply $snmp->{updates}, [{ Community => 'public@red' }], 'with its template';
  is snmp_vrf_context($snmp, $device, { name => 'blue', contexts => [{ kind => 'vrf' }] }), undef,
    'no template for the version, no switch, undef as for a refused suffix';
  is scalar @{ $snmp->{updates} }, 1, 'nothing more sent';
};

{
  package NoVrfPlatform;
  sub new { bless {}, shift }
}

subtest 'ssh_session_wrappers__platform_without_by_vrf__no_call_false' => sub {
  my $session = MySession->new(platform => NoVrfPlatform->new, host => '192.0.2.1', ssh => 'SSH', auth => {});
  ok !$session->arpnip_by_vrf, 'arpnip_by_vrf answers false';
  ok !$session->subnets_by_vrf, 'subnets_by_vrf answers false';
};

subtest 'label_rows_by_domain__row_without_vrf__reads_default_when_multi_domain' => sub {
  is_deeply label_rows_by_domain([ { ip => '192.0.2.9' } ], 1), [ { ip => '192.0.2.9', vrf => 'default' } ],
    'absent vrf is the default table';
  is_deeply label_rows_by_domain([ { ip => '192.0.2.9', vrf => 'red' } ], 0), [ { ip => '192.0.2.9' } ],
    'single domain drops the vrf';
};

subtest 'probe_connect_info__connect_info_pass_and_no_attributes__ignore_version_added' => sub {
  my $probe = \&App::Netdisco::Util::PostgresFloor::_probe_connect_info;
  is_deeply [ $probe->({ connect_info => [ 'dbi:Pg:dbname=nd', 'nd', 'old' ], pass => 'new' }) ],
    [ 'dbi:Pg:dbname=nd', 'nd', 'new', { ignore_version => 1 } ], 'connect_info, pass wins, attributes added';
  is_deeply [ $probe->({ connect_info => [ 'dbi:Pg:dbname=nd', 'nd', 'pw', { AutoCommit => 1 } ] }) ],
    [ 'dbi:Pg:dbname=nd', 'nd', 'pw', { AutoCommit => 1, ignore_version => 1 } ], 'trailing attributes kept';
  is_deeply [ $probe->({ dsn => 'dbi:Pg:dbname=nd', user => 'nd', password => 'pw' }) ],
    [ 'dbi:Pg:dbname=nd', 'nd', 'pw', undef, { ignore_version => 1 } ], 'dsn form with no options';
};

subtest 'deploy_schema__no_label_and_alias__netdisco_label_alias_options_ignore_version' => sub {
  my @calls;
  local *DBICx::Sugar::config = sub { };
  local *DBICx::Sugar::schema = sub { push @calls, [ @_ ]; return 'schema' };
  my $plugins = { DBIC => {
    netdisco => { dsn => 'dbi:Pg:dbname=nd', options => { AutoCommit => 1 } },
    other    => { alias => 'netdisco' },
  } };
  with_settings(sub {
    is App::Netdisco::DB::Deploy::deploy_schema(), 'schema', 'returns the schema';
    App::Netdisco::DB::Deploy::deploy_schema('other');
    App::Netdisco::DB::Deploy::deploy_schema('missing');
  }, plugins => $plugins);
  is $calls[0][0], 'netdisco', 'no label means netdisco';
  is_deeply $calls[0][1]{options}, { AutoCommit => 1, ignore_version => 1 }, 'options copied with ignore_version';
  is $calls[1][1]{dsn}, 'dbi:Pg:dbname=nd', 'an alias takes its target settings';
  is_deeply $calls[2][1], { options => { ignore_version => 1 } }, 'an unknown label still skips the check';
  is_deeply $plugins->{DBIC}{netdisco}{options}, { AutoCommit => 1 }, 'the shared settings are not changed';
};

subtest 'step_outcome__forced_and_unexpected_errors__outcome_text' => sub {
  my $outcome = \&App::Netdisco::DB::Deploy::_step_outcome;
  is $outcome->({ force_step => 104 }, 104, { skipped => ['x'], unexpected => [] }), 'FORCED', 'forced with skips';
  is $outcome->({ force_step => 104 }, 104, { unexpected => ['e'] }), 'OK', 'forced step tolerates errors';
  is $outcome->({}, 104, { unexpected => [] }), 'OK', 'no errors';
  is $outcome->({}, 104, { unexpected => ['e'] }), 'applied with 1 unexpected error', 'one error';
  is $outcome->({}, 104, { unexpected => ['e', 'f'] }), 'applied with 2 unexpected errors', 'two errors';
};

subtest 'subnet_l3_domain__default_row_without_router_last__domain_0_no_query' => sub {
  my $row = App::Netdisco::DB->resultset('Subnet')->new_result({ net => '192.0.2.0/24', vrf => '' });
  is_deeply $row->l3_domain, { id => 0, name => '' }, 'default table is domain 0';
};

{
  package FakeDeviceSchema;
  our @asked;
  sub new { my ($class, %args) = @_; bless { %args }, $class }
  sub resultset { my ($self, $name) = @_; push @asked, $name; return $self }
  sub resolve_alias { push @asked, "resolve $_[1]"; return $_[0]{owner} }
  sub with_times { return $_[0] }
  sub find_or_new { return $_[1]{ip} }
}

subtest 'get_device__alias_owned_or_not__finds_the_owner_or_the_address' => sub {
  local @FakeDeviceSchema::asked;
  {
    local *App::Netdisco::Util::Device::schema = sub { FakeDeviceSchema->new(owner => '192.0.2.1') };
    is App::Netdisco::Util::Device::get_device('198.51.100.7'), '192.0.2.1', 'an alias finds its owner';
  }
  is_deeply \@FakeDeviceSchema::asked, [ 'DeviceIp', 'resolve 198.51.100.7', 'Device' ], 'resolved before the lookup';
  local *App::Netdisco::Util::Device::schema = sub { FakeDeviceSchema->new(owner => undef) };
  is App::Netdisco::Util::Device::get_device('198.51.100.8'), '198.51.100.8', 'no owner, the address itself';
};

# NX-OS

my $NXOS = 'App::Netdisco::SSHCollector::Platform::NXOS';

subtest 'nxos_listed_vrfs__duplicate_and_nameless_rows__list_not_whole' => sub {
  my $json = '{"TABLE_vrf":{"ROW_vrf":[{"vrf_name":"default"},{"vrf_name":"red"},{"vrf_name":"red"},'
    . '{"vrf_name":""},{"vrf_name":{"x":1}},"junk"]}}';
  my $ssh = Test::Netdisco::FakeSSH->new(text => "#--- show vrf | json\n$json\n");
  my ($names, $whole) = $NXOS->can('_listed_vrfs')->('nx', $ssh);
  is_deeply $names, [ 'default', 'red' ], 'each name once';
  is $whole, 0, 'a row with no usable name spoils the list';

  $ssh = Test::Netdisco::FakeSSH->new(text => "#--- show vrf | json\n{\"TABLE_vrf\":{\"ROW_vrf\":[{\"vrf_name\":\"default\"},{\"vrf_name\":\"red\"},{\"vrf_name\":\"red\"}]}}\n");
  ($names, $whole) = $NXOS->can('_listed_vrfs')->('nx', $ssh);
  is $whole, 1, 'a repeated name alone does not';
};

subtest 'nxos_request_chunks__no_names__no_chunks' => sub {
  is_deeply [ $NXOS->can('_request_chunks')->() ], [], 'nothing to ask, no request';
};

subtest 'nxos_document_identity__neither_table__nothing' => sub {
  my $identity = $NXOS->can('_document_identity');
  is_deeply [ $identity->({ TABLE_vrf => { ROW_vrf => { 'vrf-name-out' => 'red' } } }) ], [], 'no count, no afi';
  is_deeply [ $identity->({ TABLE_vrf => [] }) ], [], 'table not a hash';
  is_deeply [ $identity->({ TABLE_vrf => { ROW_vrf => [ {}, {} ] } }) ], [], 'two rows';
  is_deeply [ $identity->({}) ], [], 'no table';
  is_deeply [ $identity->({ TABLE_vrf => { ROW_vrf => 'text' } }) ], [], 'a row that is not a hash';
};

subtest 'nxos_read_chained__document_with_no_vrf_name__ignored' => sub {
  my $command = $NXOS->can('_chain_command')->('red');
  my $doc = '{"TABLE_vrf":{"ROW_vrf":{"cnt-total":"0"}}}';
  my $ssh = Test::Netdisco::FakeSSH->new(text => "#--- $command\n$doc\n");
  my %reads = $NXOS->can('_read_chained')->('nx', $ssh, ['red']);
  is_deeply \%reads, {}, 'a document naming no VRF reads nothing';
};

subtest 'nxos_family_read__malformed_documents__unread_or_rows_skipped' => sub {
  my $read = $NXOS->can('_family_read');
  my $unread = { whole => 0, entries => [] };
  is_deeply $read->({}, 6), $unread, 'IPv6 with no afi table';
  is_deeply $read->({ TABLE_afi => { ROW_afi => { afi => 'ipv4' } } }, 6), $unread, 'afi not ipv6';
  is_deeply $read->({ TABLE_afi => { ROW_afi => { count => '1' } } }, 6), $unread, 'afi missing';
  is_deeply $read->({ 'cnt-total' => 'many' }, 4), $unread, 'count not a number';
  is_deeply $read->({ 'cnt-total' => undef }, 4), $unread, 'count absent';
  my $rows = { 'cnt-total' => '3', TABLE_adj => { ROW_adj => [
    { 'ip-addr-out' => '10.0.0.1', mac => '0200.0000.0001' },
    { 'ip-addr-out' => '10.0.0.2', mac => 'INCOMPLETE' },
    { mac => '0200.0000.0003' },
    { 'ip-addr-out' => '10.0.0.4' },
  ] } };
  $rows->{'cnt-total'} = '4';
  is_deeply $read->($rows, 4), { whole => 1, entries => [ { ip => '10.0.0.1', mac => '02:00:00:00:00:01' } ] },
    'rows without a usable address or MAC counted, not stored';
};

subtest 'nxos_row_prefixes__prefix_absent_or_not_text__skipped' => sub {
  my $vrf_row = { TABLE_addrf => { ROW_addrf => { TABLE_prefix => { ROW_prefix => [
    { ipprefix => '10.0.0.0/24' }, { ipv6prefix => '2001:db8::/64' }, { ipprefix => [] }, {}, { ipprefix => '10.9.0.1' },
  ] } } } };
  is_deeply [ $NXOS->can('_row_prefixes')->($vrf_row) ],
    [ { prefix => '10.0.0.0', len => 24 }, { prefix => '2001:db8::', len => 64 }, { prefix => '10.9.0.1', len => undef } ],
    'text prefixes kept, a missing length left undef';
};

# IOS-XE

my $IOSXE = 'App::Netdisco::SSHCollector::Platform::IOSXE';

my $IOSXE_LIST = <<'END';
  Name                             Default RD            Protocols   Interfaces
  red                              64512:10              ipv4,ipv6   Gi2
  ----------------------------------------------------------------------
Platform iVRF Name                 Default RD            Protocols   Interfaces
  junk line that would spoil the list
END

subtest 'iosxe_vrf_list_whole__dash_line_and_platform_section__whole' => sub {
  is $IOSXE->can('_vrf_list_whole')->($IOSXE_LIST), 1, 'dashes skipped, the platform section ends the list';
};

subtest 'iosxe_parse_vrf_protocols__undef_and_platform_section__stops' => sub {
  my $parse = $IOSXE->can('_parse_vrf_protocols');
  is_deeply $parse->(undef), {}, 'no text, no protocols';
  is_deeply $parse->($IOSXE_LIST . "  blue   64512:11   ipv4   Gi3\n"), { red => 'ipv4,ipv6' },
    'nothing after the platform section';
};

subtest 'iosxe_vrf_steps__vrf_not_in_protocols__ipv6_asked' => sub {
  my $state = {};
  is_deeply [ $IOSXE->can('_vrf_steps')->('red', {}, 1, $state) ],
    [ [ 'red', 4, 'show ip arp vrf red' ], [ 'red', 6, 'show ipv6 neighbors vrf red' ] ],
    'unknown protocols assume IPv6';
};

subtest 'iosxe_parse_neighbor_row__incomplete_and_unrecognized__counted_or_not' => sub {
  my $row = $IOSXE->can('_parse_neighbor_row');
  is_deeply [ $row->('2001:DB8::5   0  -   INCMP  Gi2') ], [1], 'INCMP without a MAC is a row with no entry';
  is_deeply [ $row->('2001:DB8::5   0  -   STALE  Gi2') ], [0], 'another state without a MAC is not';
  is_deeply [ $row->('garbage') ], [0], 'not a row';
};

# IOS-XR

my $IOSXR = 'App::Netdisco::SSHCollector::Platform::IOSXR';

subtest 'iosxr_parse_vrf_list__default_and_repeated_rows__listed_once' => sub {
  my $text = "VRF                  RD                  RT                         AFI   SAFI\n"
    . "default              not set\nred                  64512:10\nred                  64512:10\n";
  my ($names, $names_whole, $whole) = $IOSXR->can('_parse_vrf_list')->($text);
  is_deeply $names, [ 'red' ], 'default left out, red once';
  is $names_whole, 1, 'a repeated row does not spoil the names';
  is $whole, 1, 'still a whole list';
  ($names, $names_whole, $whole) = $IOSXR->can('_parse_vrf_list')->("% Invalid input detected\n");
  is $whole, 0, 'an error and no header is not a list';
};

subtest 'iosxr_rows__incomplete_states__rows_with_no_entry' => sub {
  is_deeply [ $IOSXR->can('_parse_arp_row')->('10.0.0.9  -  0000.0000.0000  Incomplete  ARPA  Gi0/0/0/0') ], [1, undef],
    'an incomplete ARP row';
  is_deeply [ $IOSXR->can('_parse_neighbor_row')->('2001:db8::9  0  0000.0000.0000  INCMP  Gi0/0/0/0') ], [1, undef],
    'an INCMP neighbor row';
};

subtest 'iosxr_read_table__repeated_row__stored_once' => sub {
  my $row = '10.60.0.2       00:00:31   0200.0000.0601  Dynamic    ARPA  GigabitEthernet0/0/0/0';
  my ($exp) = fake_expect("#prompt: RP/0/RP0/CPU0:router#\n#--- show arp vrf red\n"
    . "Address         Age        Hardware Addr   State      Type  Interface\n$row\n$row\n");
  my $state = {};
  $IOSXR->can('_read_table')->('router', $state, $exp, 5, 'red', 4, 'show arp vrf red');
  is scalar @{ $state->{entries} }, 1, 'one entry';
  is $state->{whole}{red}{4}, 1, 'read whole';
};

# EOS

my $EOS = 'App::Netdisco::SSHCollector::Platform::EOS';

subtest 'eos_arpnip__vrf_without_neighbor_list__contributes_nothing' => sub {
  my $ssh = Test::Netdisco::FakeSSH->new(text => "#--- show ip arp vrf all | json | no-more\n"
    . '{"vrfs":{"red":{},"blue":{"ipV4Neighbors":[{"address":"10.0.0.1","hwAddress":"02:00:00:00:00:01","interface":"Vlan1,,Po1"},{"address":"10.0.0.2"},{"hwAddress":"02:00:00:00:00:03"}]}}}'
    . "\n#--- show ipv6 neighbor vrf all | json | no-more\n" . '{"vrfs":{}}' . "\n");
  my @entries = $EOS->new->arpnip('eos', $ssh, {});
  is_deeply [ sort map { join ' ', $_->{ip}, $_->{iface} // '-' } @entries ], [ '10.0.0.1 -', '10.0.0.1 Po1', '10.0.0.1 Vlan1' ],
    'no list and no MAC give nothing; an empty interface name gives an entry without one';
};

subtest 'eos_subnets_by_vrf__malformed_tables__skipped_rest_read' => sub {
  my $ssh = Test::Netdisco::FakeSSH->new(text => "#--- show ip route vrf all connected | json | no-more\n"
    . '{"vrfs":{"red":{"routes":{"10.0.0.0/24":{},"10.9.9.9":{}}},"blue":[],"green":{"routes":[]},"grey":{}}}'
    . "\n#--- show ipv6 route vrf all connected | json | no-more\n" . '{"vrfs":[]}' . "\n");
  my $got = $EOS->new->subnets_by_vrf('eos', $ssh, {});
  is_deeply $got, { red => [ { prefix => '10.0.0.0', len => 24 }, { prefix => '10.9.9.9', len => undef } ], grey => [] },
    'a table or routes that are not a hash contribute nothing; a key with no length is kept for the worker';

  $ssh = Test::Netdisco::FakeSSH->new(text => "#--- show ip route vrf all connected | json | no-more\n[]\n"
    . "#--- show ipv6 route vrf all connected | json | no-more\n\"text\"\n");
  is $EOS->new->subnets_by_vrf('eos', $ssh, {}), undef, 'replies that are not objects read nothing';
};

# VOSS

my $VOSS = 'App::Netdisco::SSHCollector::Platform::VOSS';

subtest 'voss_expand_vrf_ids__ranges_numbers_and_junk__numbers' => sub {
  is_deeply [ $VOSS->can('_expand_vrf_ids')->('3-4,x,512') ], [ 3, 4, 512 ], 'junk dropped';
};

subtest 'voss_compress_ipv6__unparsable__undef' => sub {
  is $VOSS->can('_compress_ipv6')->('1:::2'), undef, 'not an address';
  is $VOSS->can('_compress_ipv6')->('2001:db8:0:0:0:0:0:10'), '2001:db8::10', 'compressed';
};

subtest 'voss_parse_blocks__global_router_bad_address_and_orphan_mac__handled' => sub {
  my $arp = $VOSS->can('_parse_arp_blocks')->('edge', "  IP Arp - GlobalRouter\n10.0.0.1  02:00:00:00:00:01  1/1\n"
    . "1 out of 1 ARP entries displayed\n");
  is_deeply $arp->{rows}, { '' => 1 }, 'GlobalRouter is the empty name';
  my $nd = $VOSS->can('_parse_neighbor_blocks')->('edge', join "\n",
    'Neighbor Information - GlobalRouter',
    '      02:00:00:00:00:09',
    '1:::2/   static  1/1',
    '      02:00:00:00:00:01',
    '2001:db8:0:0:0:0:0:10/   static  1/1',
    '      02:00:00:00:00:02',
    '2 out of 2 Total Num of Neighbor Entries displayed', '');
  is_deeply $nd->{rows}, { '' => 2 }, 'both address lines counted';
  is_deeply [ map { "$_->{ip} $_->{mac}" } @{ $nd->{entries} } ], [ '2001:db8::10 02:00:00:00:00:02' ],
    'a MAC with no address line and an unparsable address give no entry';
};

subtest 'voss_vrf_result__no_instance_id_not_listed__ignored' => sub {
  # the global table is read for ARP but not for IPv6, so an unmapped id
  # wrongly taken as the empty name would mark it whole
  my $result = $VOSS->can('_vrf_result')->([ '', 'red' ], { 1 => 'red' },
    { entries => [], read => { '' => 1, red => 1 } }, { entries => [], read => {}, no_instance => [ 1, 7 ] }, 1);
  is_deeply $result->{vrf_read}, { '' => 0, red => 1 }, 'red has no IPv6 instance; id 7 names no VRF';
};

subtest 'voss_read_blocks__error_line__nothing_read' => sub {
  my @logged;
  {
    local *App::Netdisco::SSHCollector::Platform::VOSS::debug = sub { push @logged, join '', @_ };
    my ($exp) = fake_expect("#prompt: edge1:1>\n#--- show ip arp vrfids 0-512\n% Invalid input detected at '^' marker.\n");
    is_deeply [ $VOSS->can('_read_blocks')->('edge', $exp, 'ARP', 'show ip arp vrfids 0-512', sub { {} }) ], [],
      'an invalid input reply fails the read';
  }
  is scalar(grep { m/: invalid command$/ } @logged), 1, 'logged as an invalid command';
  @logged = ();
  local *App::Netdisco::SSHCollector::Platform::VOSS::debug = sub { push @logged, join '', @_ };
  my ($exp) = fake_expect("#prompt: edge1:1>\n#--- show ip arp vrfids 0-512\nError : vrf id 999 not found\n");
  is_deeply [ $VOSS->can('_read_blocks')->('edge', $exp, 'ARP', 'show ip arp vrfids 0-512', sub { {} }) ], [],
    'an Error line fails the read';
  is scalar(grep { m/error fetching ARP \[edge\] : show ip arp vrfids 0-512 : vrf id 999 not found/ } @logged), 1,
    'the device error is logged';
};

# arpnip workers

my $NODES = 'App::Netdisco::Worker::Plugin::Arpnip::Nodes';

subtest 'drop_flattened_twins__entries_without_mac_or_ip__kept' => sub {
  vars->{'arps'} = [
    { mac => '02:00:00:00:00:01', ip => '10.0.0.1', vrf => 'red' },
    { mac => '02:00:00:00:00:01', ip => '10.0.0.1', vrf => '', flattened => 1 },
    { node => '02:00:00:00:00:02', ip => '10.0.0.2', flattened => 1 },
    { ip => '10.0.0.3', vrf => 'red' },
    { mac => '02:00:00:00:00:04', vrf => '', flattened => 1 },
  ];
  $NODES->can('drop_flattened_twins')->($device);
  is_deeply [ map { join '|', $_->{ip} // '-', $_->{vrf} // '-' } @{ vars->{'arps'} } ],
    [ '10.0.0.1|red', '10.0.0.2|-', '10.0.0.3|red', '-|' ], 'only the flattened twin dropped';
  delete vars->{'arps'};
};

subtest 'drop_own_entries__entries_without_mac_or_ip__kept' => sub {
  local *App::Netdisco::Worker::Plugin::Arpnip::Nodes::own_identity = sub {
    return ({ '02:00:00:00:00:aa' => 1 }, { '02:00:00:00:00:bb' => 1 }, { join(chr(28), '', '10.0.0.5') => 1 });
  };
  vars->{'vrf_read'} = { '' => 1 };
  vars->{'arps'} = [
    { ip => '10.0.0.1' },
    { node => '02:00:00:00:00:aa', ip => '10.0.0.2' },
    { mac => '02:00:00:00:00:bb' },
    { mac => '02:00:00:00:00:bb', ip => '10.0.0.5' },
  ];
  $NODES->can('drop_own_entries')->($device);
  is_deeply [ map { join '|', $_->{ip} // '-', $_->{mac} // '-' } @{ vars->{'arps'} } ],
    [ '10.0.0.1|-', '-|02:00:00:00:00:bb' ], 'own MAC and own address dropped; no MAC or no IP kept';
  delete @{ vars() }{qw/arps vrf_read/};
};

{
  package ResultSession;
  sub new { my ($class, $result) = @_; bless { result => $result }, $class }
  sub arpnip_by_vrf { return $_[0]{result} }
}

subtest 'gather_arps_by_vrf_cli__empty_result_and_vrfless_entry__done_unvouched' => sub {
  delete @{ vars() }{qw/arps vrf_read vrf_read_families vrf_list_complete/};
  my $status = $NODES->can('gather_arps_by_vrf_cli')->($device, ResultSession->new({}));
  is $status->status, 'done', 'an empty result is a read of nothing, not a defer';
  is_deeply vars->{'vrf_read'}, undef, 'no VRF vouched';
  is vars->{'vrf_list_complete'}, 0, 'nor the list';

  delete @{ vars() }{qw/arps vrf_read vrf_read_families vrf_list_complete/};
  $NODES->can('gather_arps_by_vrf_cli')->($device, ResultSession->new({
    entries => [ { mac => '02:00:00:00:00:01', ip => '10.0.0.1' } ], vrf_read => { red => 1 }, vrf_list_complete => 1 }));
  is_deeply [ map { $_->{vrf} } values %{ vars->{'arps'} } ], [ '' ], 'an entry with no vrf is the default table';
  is vars->{'vrf_read'}{''}, 0, 'and proves no read of it';
  delete @{ vars() }{qw/arps vrf_read vrf_read_families vrf_list_complete/};
};

subtest 'gather_arps_by_vrf_cli__default_and_empty_both_read__whole_only_if_both' => sub {
  foreach my $case ([ 0, 1 ], [ 1, 0 ], [ 1, 1 ]) {
    delete @{ vars() }{qw/arps vrf_read vrf_read_families vrf_list_complete/};
    $NODES->can('gather_arps_by_vrf_cli')->($device, ResultSession->new({
      vrf_read => { default => $case->[0], '' => $case->[1] }, vrf_list_complete => 1, families => [ 4, 6 ] }));
    is vars->{'vrf_read'}{''}, ($case->[0] && $case->[1]) ? 1 : 0, "default $case->[0] and '' $case->[1]";
  }
  delete @{ vars() }{qw/arps vrf_read vrf_read_families vrf_list_complete/};
};

subtest 'well_formed_families__bad_values__not_well_formed' => sub {
  my $check = $NODES->can('_well_formed_families');
  ok !$check->([ 4, undef ]), 'undef member';
  ok !$check->([ 4, 5 ]), 'unknown family';
  ok !$check->([]), 'empty';
  ok $check->([ 6, 4 ]), 'both families';
};

my $SUBNETS = 'App::Netdisco::Worker::Plugin::Arpnip::Subnets';

subtest 'vrf_subnet_cidr__unparsable_unspecified_and_private_v6__undef' => sub {
  my $cidr = $SUBNETS->can('vrf_subnet_cidr');
  with_settings(sub {
    is $cidr->({ prefix => '10.0.0.256', len => 24 }), undef, 'unparsable prefix';
    is $cidr->({ len => 24 }), undef, 'no prefix';
    is $cidr->({ prefix => '0.0.0.0', len => 8 }), undef, 'unspecified';
    is $cidr->({ prefix => '10.0.0.0', len => 33 }), undef, 'a length past the family';
    is $cidr->({ prefix => 'fd00:1::', len => 64 }), 'fd00:1:0:0:0:0:0:0/64', 'ULA kept by default';
  }, ignore_private_nets => 0);
  with_settings(sub {
    is $cidr->({ prefix => 'fd00:1::', len => 64 }), undef, 'ULA dropped with ignore_private_nets';
    is $cidr->({ prefix => '2001:db8::', len => 64 }), '2001:db8:0:0:0:0:0:0/64', 'global IPv6 kept';
  }, ignore_private_nets => 1);
};

subtest 'store_vrf_subnets__complete_read_without_data__nothing_stored' => sub {
  delete vars->{'subnets'};
  local *App::Netdisco::Worker::Plugin::Arpnip::Subnets::each_vrf_instance = sub {
    return { red => { complete => 1, data => undef }, blue => { complete => 0, data => { x => { prefix => '10.0.0.0', len => 24 } } } };
  };
  my $status = $SUBNETS->can('store_vrf_subnets')->($device, undef, {});
  like $status->log, qr/processed 0 Subnet entries/, 'nothing counted';
  is vars->{'subnets'}, undef, 'nothing stored, not even for the incomplete VRF';
};

done_testing;
