#!/usr/bin/env perl

# Database roles from the ACL Manager used to reach the port control checks
# only through sync_portctl_roles(), which every caller had to remember to run
# first and which rewrote the global portctl_by_role and host_groups in place.
# effective_setting() now lays the database ACLs over the YAML on first use,
# at most once per web request or backend job, without touching the global
# config, and the checks read nothing else. These tests pin the merge, the
# caching, the group lookup order in check_acl, and that the next job sees a
# change with no sync anywhere.
#
# Only the database read is faked (Test::Netdisco::ManagedACL); the merge and
# the checks are the real ones.

use strict;
use warnings;
no warnings 'once';

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; delete $ENV{ND2_DO_FORCE} }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };
use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB; # Device rows built in memory, never stored
use App::Netdisco::Backend::Job;
use App::Netdisco::Worker::Plugin::DumpConfig; # registers its worker in vars
use JSON::PP ();
use Dancer qw/:moose :script !pass/;
use App::Netdisco::Util::Configuration qw/effective_setting forget_effective_config/;
use App::Netdisco::Util::Permission qw/check_acl acl_matches_only/;
use App::Netdisco::Util::Port qw/port_acl_by_role_check device_acl_by_role_check/;
use Test::Netdisco::ManagedACL 'stub_managed_acls';

config->{logger} = 'null';

my $IN  = '192.0.2.1';
my $OUT = '192.0.2.99';

my $DIN  = { ip => $IN };
my $DOUT = { ip => $OUT };
my $PORT = { ip => $IN, port => 'Gi1/1' };

{ package Test::FakeUser;
  sub new { my ($c, %a) = @_; return bless { port_control => 1, admin => 0, portctl_role => '', %a }, $c }
  sub port_control { $_[0]->{port_control} }
  sub admin        { $_[0]->{admin} }
  sub portctl_role { $_[0]->{portctl_role} }
}

{ package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

# runs the dumpconfig worker as netdisco-do -Q does, returning what it printed
sub dumpconfig_json {
  my $key = shift;
  local $ENV{ND2_DO_QUIET} = 1;
  my ($worker) = @{ vars->{'workers'}->{'dumpconfig'}->{'main'}->{'_base_'}->{0} };
  my $job = App::Netdisco::Backend::Job->new({
    job => 0, action => 'dumpconfig', subaction => $key });
  return JSON::PP->new->allow_nonref->decode( $worker->($job)->log );
}

subtest 'effectiveSetting__a_setting_with_no_database_content__is_the_yaml_value' => sub {
  stub_managed_acls({});
  setting('snmptimeout' => 1234);
  is effective_setting('snmptimeout'), 1234, 'an unrelated setting reads straight from YAML';
};

subtest 'effectiveSetting__database_roles__are_laid_over_the_yaml_without_changing_it' => sub {
  setting('host_groups')->{yamlgroup} = [$IN];
  setting('portctl_by_role' => { yamlrole => 'group:yamlgroup', clash => [$OUT], empty => '' });
  # sorted by name: clash gets left ACL 1, dbrole gets left 2 and right 3
  stub_managed_acls({ clash  => [ [[$IN]] ],
                      dbrole => [ [[$IN], ['port:Gi1/1']] ] });

  my $roles  = effective_setting('portctl_by_role');
  my $groups = effective_setting('host_groups');

  is $roles->{yamlrole}, 'group:yamlgroup', 'a YAML role is kept';
  is $roles->{empty}, '!group:__ANY__', 'a YAML role with no value refuses everything';
  is_deeply $roles->{dbrole}, { 'group:synthesized_group_netdisco_2' => ['port:Gi1/1'] },
    'a database role maps its synthesized device group to its port rules';
  is_deeply $roles->{clash}, { 'group:synthesized_group_netdisco_1' => undef },
    'a database role replaces a YAML role of the same name';
  is_deeply $groups->{synthesized_group_netdisco_2}, [$IN],
    'the synthesized group holds the device rules';
  is_deeply $groups->{yamlgroup}, [$IN], 'YAML groups are kept';

  is_deeply setting('portctl_by_role'),
    { yamlrole => 'group:yamlgroup', clash => [$OUT], empty => '' },
    'the YAML portctl_by_role is untouched';
  ok !(grep { m/^synthesized_group_/ } keys %{ setting('host_groups') }),
    'no synthesized group is written into the YAML host_groups';

  delete setting('host_groups')->{yamlgroup};
  setting('portctl_by_role' => {});
};

subtest 'effectiveSetting__the_tenant__is_part_of_each_synthesized_group_name' => sub {
  stub_managed_acls({ dbrole => [ [[$IN], ['port:Gi1/1']] ] });

  var tenant => 'east';
  ok exists effective_setting('host_groups')->{synthesized_group_east_1},
    'a tenant names its own groups';

  var tenant => 'netdisco';
  forget_effective_config();
  ok exists effective_setting('host_groups')->{synthesized_group_netdisco_1},
    'the default tenant by its tag';

  var tenant => undef;
  forget_effective_config();
  ok exists effective_setting('host_groups')->{synthesized_group_netdisco_1},
    'and the default tenant when none is set';
};

subtest 'effectiveSetting__many_reads__load_the_database_once' => sub {
  my $calls = stub_managed_acls({ dbrole => [ [[$IN]] ] });
  effective_setting('portctl_by_role') for 1 .. 5;
  effective_setting('host_groups');
  is $$calls, 1, 'one load serves every read';

  forget_effective_config();
  effective_setting('portctl_by_role');
  is $$calls, 2, 'forget_effective_config makes the next read load again';
};

subtest 'checkAcl__a_group_yaml_defines__is_found_without_the_database' => sub {
  my $calls = stub_managed_acls({});
  setting('host_groups')->{yamlgroup} = [$IN];
  ok check_acl($IN, ['group:yamlgroup']), 'the YAML group matches';
  is $$calls, 0, 'and the database was never read';
  delete setting('host_groups')->{yamlgroup};
};

subtest 'checkAcl__a_synthesized_group__is_found_through_the_overlay' => sub {
  stub_managed_acls({ dbrole => [ [[$IN]] ] });
  ok  check_acl($IN,  ['group:synthesized_group_netdisco_1']), 'its device matches';
  ok !check_acl($OUT, ['group:synthesized_group_netdisco_1']), 'another device does not';
};

subtest 'checkAcl__an_unknown_group__matches_nothing_and_is_not_written_into_config' => sub {
  stub_managed_acls({});
  ok !check_acl($IN, ['group:nosuchgroup']),  'nothing matches it';
  ok  check_acl($IN, ['!group:nosuchgroup']), 'so its negation matches';
  ok !exists setting('host_groups')->{nosuchgroup}, 'and host_groups gains no key';
};

subtest 'checkAcl__the_database_unreachable__leaves_an_unknown_group_matching_nothing' => sub {
  stub_managed_acls(undef, dies => "could not connect to server\n");
  my $matched = eval { check_acl($IN, ['group:synthesized_group_netdisco_1']) };
  is $@, '', 'check_acl does not die';
  ok !$matched, 'the group matches nothing';
  ok check_acl($IN, ['!group:synthesized_group_netdisco_1']), 'and its negation matches, as today';
};

subtest 'roleChecks__database_roles__decide_as_sync_portctl_roles_did' => sub {
  setting('portctl_by_role' => { yamlrole => [$IN], clash => [$OUT], empty => '' });
  stub_managed_acls({
    anyport => [ [[$IN], []] ],             # an empty port list: any port
    noports => [ [[$IN], undef] ],          # port rules undef: no port
    gi11    => [ [[$IN], ['port:Gi1/1']] ],
    clash   => [ [[$IN]] ],                 # no right ACL row at all
    norows  => [],
  });
  my $as   = sub { Test::FakeUser->new(portctl_role => shift) };
  my $gi12 = { ip => $IN, port => 'Gi1/2' };

  ok  port_acl_by_role_check($PORT, $DIN,  $as->('anyport')), 'an empty port list allows any port on the device';
  ok !port_acl_by_role_check($PORT, $DOUT, $as->('anyport')), 'but not on another device';
  ok !port_acl_by_role_check($PORT, $DIN,  $as->('noports')), 'port rules of undef refuse at port level';
  ok  device_acl_by_role_check($DIN, $as->('noports')),      'and still match at device level';
  ok  port_acl_by_role_check($PORT, $DIN, $as->('gi11')),     'a listed port is allowed';
  ok !port_acl_by_role_check($gi12, $DIN, $as->('gi11')),     'an unlisted port is refused';
  ok !port_acl_by_role_check($PORT, $DIN, $as->('clash')),    'a row with no right ACL refuses at port level';
  ok  device_acl_by_role_check($DIN,  $as->('clash')),        'the database role replaced the YAML one of that name';
  ok !device_acl_by_role_check($DOUT, $as->('clash')),        'so the YAML device no longer counts';
  ok !port_acl_by_role_check($PORT, $DIN, $as->('norows')),   'a database role with no rows refuses ports';
  ok !device_acl_by_role_check($DIN, $as->('norows')),        'and devices';
  ok !port_acl_by_role_check($PORT, $DIN, $as->('empty')),    'a YAML role with no value refuses';
  ok  port_acl_by_role_check($PORT, $DIN, $as->('yamlrole')), 'a YAML device role still allows its device';

  setting('portctl_by_role' => {});
};

subtest 'roleChecks__netdisco_do_force__never_loads_the_roles' => sub {
  my $calls = stub_managed_acls({ any => [ [[$IN], []] ] });
  local $ENV{ND2_DO_FORCE} = 1;
  my $user = Test::FakeUser->new(portctl_role => 'any');
  ok port_acl_by_role_check($PORT, $DOUT, $user), 'the port check passes';
  ok device_acl_by_role_check($DOUT, $user), 'the device check passes';
  is $$calls, 0, 'and the database was never read';
};

subtest 'roleChecks__a_token_acl_group_with_the_same_acl_id__is_not_confused_with_a_role' => sub {
  # refresh_managed_acl leaves a token ACL's groups in the global host_groups,
  # named by ACL id alone, and the role's rows have the same ids here
  setting('host_groups')->{synthesized_group_5} = [$OUT];
  setting('host_groups')->{api_office_only}     = ['group:synthesized_group_5'];
  stub_managed_acls({ leafonly => [ [[$IN], []] ] }, first_id => 5);
  my $user = Test::FakeUser->new(portctl_role => 'leafonly');

  ok  port_acl_by_role_check($PORT, $DIN,  $user), 'the role uses its own device rules';
  ok !port_acl_by_role_check($PORT, $DOUT, $user), 'not the token ACL group of the same id';
  ok  acl_matches_only($OUT, setting('host_groups')->{api_office_only}),
    'and the token ACL still matches its own address';

  delete setting('host_groups')->{$_} for qw/synthesized_group_5 api_office_only/;
};

subtest 'runner__the_next_job_in_one_process__sees_a_changed_role' => sub {
  config->{'extra_worker_plugins'} = ['X::TestRoles'];
  config->{'device_auth'} = [];
  my $user = Test::FakeUser->new(portctl_role => 'leafonly');

  my $run = sub {
    my $job = App::Netdisco::Backend::Job->new({
      job => 0, action => 'testroles', username => $user,
      device => App::Netdisco::DB->resultset('Device')->new_result({ ip => $IN }),
    });
    MyWorker->new->run($job);
    return $job->status;
  };

  stub_managed_acls({ leafonly => [ [[$IN], []] ] });
  is $run->(), 'done', 'the first job sees the role covering its device';

  # the ACL Manager drops the device from the role between the two jobs.
  # keep_cache leaves the first job's overlay in place, as netdisco-do would
  stub_managed_acls({ leafonly => [ [[$OUT], []] ] }, keep_cache => 1);
  is $run->(), 'error', 'the next job sees the change, because run() starts afresh';

  config->{'extra_worker_plugins'} = [];
};

subtest 'dumpconfig__portctl_by_role_and_host_groups__print_the_effective_values' => sub {
  setting('portctl_by_role' => { yamlrole => [$IN] });
  stub_managed_acls({ dbrole => [ [[$IN], ['port:Gi1/1']] ] });

  is_deeply [ sort keys %{ dumpconfig_json('portctl_by_role') } ], [qw/dbrole yamlrole/],
    '-e portctl_by_role shows the YAML and database roles';
  ok exists dumpconfig_json('host_groups')->{synthesized_group_netdisco_1},
    '-e host_groups shows the synthesized group';

  my $all = dumpconfig_json('');
  ok exists $all->{portctl_by_role}->{dbrole}, 'a full dump carries the effective roles';
  ok exists $all->{host_groups}->{synthesized_group_netdisco_1}, 'and the effective groups';
  is dumpconfig_json('snmptimeout'), setting('snmptimeout'), 'any other key prints its YAML value';

  setting('portctl_by_role' => {});
};

subtest 'dumpconfig__the_database_unreachable__prints_the_yaml_with_one_warning' => sub {
  my @warned;
  no warnings 'redefine';
  local *App::Netdisco::Worker::Plugin::DumpConfig::warning = sub { push @warned, join '', @_ };
  setting('portctl_by_role' => { yamlrole => [$IN] });
  stub_managed_acls(undef, dies => "could not connect to server\n");

  is_deeply dumpconfig_json('portctl_by_role'), { yamlrole => [$IN] },
    '-e portctl_by_role falls back to the YAML';

  @warned = ();
  my $all = dumpconfig_json('');
  is_deeply $all->{portctl_by_role}, { yamlrole => [$IN] }, 'a full dump falls back too';
  is scalar @warned, 1, 'with one warning, not one per key';
  like $warned[0], qr/database ACLs not included/, 'saying why';

  setting('portctl_by_role' => {});
};

subtest 'cleanup__the_yaml_backup_and_the_unused_loader__are_gone' => sub {
  ok !exists config->{'portctl_by_role_shadow'},
    'no backup of portctl_by_role is kept, because nothing rewrites it';
  ok !App::Netdisco::Util::Configuration->can('load_acls_from_database'),
    'load_acls_from_database, unused since #1651, is gone';
};

done_testing;
