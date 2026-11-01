#!/usr/bin/env perl

# The loader writes ACL Manager roles (host_port ACLs) and named groups (host
# ACLs) into CONFIG, so that setting() and check_acl() never touch the
# database. The two database reads are stubbed; everything above them is real.
#
# Two rules here are easy to break without noticing:
# - the counter is read before the rows, or a change committed between the two
#   reads would be stored under the new counter and never reloaded;
# - a failed read leaves CONFIG alone only until something has been loaded,
#   after which it must go back to the YAML, or a worker keeps stale (or
#   another tenant's) roles after the database goes away.

use strict;
use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use lib 'xt/lib';
use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };
use Scalar::Util 'refaddr';
use Storable 'dclone';

# first, so that the environment and config are set up before Dancer loads
use App::Netdisco::Util::ManagedConfig qw(
  load_managed_config capture_yaml_settings yaml_setting
);
use Test::Netdisco::ManagedACL qw(stub_managed_config);
use App::Netdisco::Util::Permission qw(check_acl);
use Dancer qw/:syntax :script !pass/;

my $IN  = '192.0.2.1';
my $OUT = '192.0.2.99';

my $SHIPPED_GROUPS = dclone(setting('host_groups') || {});

# sets the YAML values and takes the clean copy again, as at startup
sub yaml {
  my %args = @_;
  config->{'portctl_by_role'} = $args{roles} || {};
  config->{'host_groups'} = { %{ dclone($SHIPPED_GROUPS) }, %{ $args{groups} || {} } };
  capture_yaml_settings();
}

sub normalized {
  my $roles = shift;
  return { map { ($_ => ($roles->{$_} || '!group:__ANY__')) } keys %$roles };
}

sub synth_keys { return [ sort grep { /^synthesized_group_/ } keys %{ setting('host_groups') } ] }

subtest 'loader__nothing_loaded_and_reads_fail__leaves_config_alone' => sub {
  yaml();
  config->{'portctl_by_role'} = { t => [$IN] };
  my $before = setting('portctl_by_role');
  my $groups = setting('host_groups');

  stub_managed_config(version => sub { die "no database\n" });
  load_managed_config();

  is_deeply(setting('portctl_by_role'), { t => [$IN] }, 'roles as the test set them');
  is(refaddr(setting('portctl_by_role')), refaddr($before), 'roles not even replaced');
  is(refaddr(setting('host_groups')), refaddr($groups), 'groups not replaced');
};

subtest 'loader__roles_merge_over_yaml_roles_of_the_same_name' => sub {
  yaml(roles => { yamlrole => 'group:yg', clash => [$OUT], empty => '' });
  stub_managed_config(version => 1, rows => { netdisco => {
    clash  => { type => 'host_port', maps => [ [[$IN]] ] },
    dbrole => { type => 'host_port', maps => [ [[$IN], ['port:Gi1/1']] ] },
  }});
  load_managed_config();

  my $roles = setting('portctl_by_role');
  is($roles->{yamlrole}, 'group:yg', 'yaml role unchanged');
  is($roles->{empty}, '!group:__ANY__', 'empty yaml role refuses everything');
  is_deeply($roles->{clash}, { 'group:synthesized_group_netdisco_1' => undef },
    'database role replaces yaml role, undef port side kept');
  is_deeply($roles->{dbrole}, { 'group:synthesized_group_netdisco_2' => ['port:Gi1/1'] },
    'database role maps device group to port rules');
  is_deeply(setting('host_groups')->{synthesized_group_netdisco_2}, [$IN],
    'synthesized group holds the device rules');
};

subtest 'loader__host_acls_become_named_groups_over_yaml' => sub {
  yaml(groups => { office => [$OUT] });
  stub_managed_config(version => 1, rows => { netdisco => {
    office => { type => 'host', maps => [ [[$IN]] ] },
  }});
  load_managed_config();

  ok(check_acl($IN, ['group:office']), 'database rules match');
  ok(!check_acl($OUT, ['group:office']), 'yaml rules replaced');
};

subtest 'loader__an_empty_host_acl__replaces_a_yaml_group_and_matches_nothing' => sub {
  yaml(groups => { office => [$IN] });
  stub_managed_config(version => 1, rows => { netdisco => {
    office => { type => 'host', maps => [] },
  }});
  load_managed_config();

  is_deeply(setting('host_groups')->{office}, [], 'empty group');
  ok(!check_acl($IN, ['group:office']), 'fails closed');
};

subtest 'loader__a_deleted_row_disappears' => sub {
  yaml();
  stub_managed_config(version => 1, rows => { netdisco => {
    a => { type => 'host_port', maps => [ [[$IN], ['port:Gi1/1']] ] },
    b => { type => 'host_port', maps => [ [[$OUT], ['port:Gi1/2']] ] },
  }});
  load_managed_config();
  ok(exists setting('portctl_by_role')->{a}, 'a loaded first');

  stub_managed_config(version => 2, first_id => 10, keep_cache => 1, rows => { netdisco => {
    b => { type => 'host_port', maps => [ [[$OUT], ['port:Gi1/2']] ] },
  }});
  load_managed_config();

  ok(!exists setting('portctl_by_role')->{a}, 'a is gone');
  is_deeply(setting('portctl_by_role')->{b},
    { 'group:synthesized_group_netdisco_10' => ['port:Gi1/2'] }, 'b reloaded');
  is_deeply(synth_keys(), ['synthesized_group_netdisco_10'], 'only b has a synthesized group');
};

subtest 'loader__an_unchanged_counter__reads_no_rows' => sub {
  yaml();
  my $calls = stub_managed_config(version => 5, rows => { netdisco => {
    r => { type => 'host_port', maps => [ [[$IN]] ] },
  }});
  load_managed_config() for 1 .. 3;

  is($calls->{version_reads}, 3, 'counter read every time');
  is($calls->{row_reads}, 1, 'rows read once');
  ok(exists setting('portctl_by_role')->{r}, 'role still applied');
};

subtest 'loader__counter_read_before_rows' => sub {
  yaml();
  # a write commits while the rows are read: the counter read after it says 2
  my $rows_read = 0;
  my $calls = stub_managed_config(
    version => sub { $rows_read ? 2 : 1 },
    rows => sub { $rows_read = 1; return { netdisco => {} } },
  );
  load_managed_config();
  load_managed_config();

  is($calls->{row_reads}, 2, 'rows read again, the first load was stored under 1');
};

subtest 'loader__tenants_have_their_own_cache_and_names' => sub {
  yaml();
  my $calls = stub_managed_config(version => 1, rows => {
    netdisco => { r => { type => 'host_port', maps => [ [[$IN], ['port:Gi1/1']] ] } },
    east     => { r => { type => 'host_port', maps => [ [[$OUT], ['port:Gi1/2']] ] } },
  });

  var tenant => undef;
  load_managed_config();

  var tenant => 'east';
  load_managed_config();
  is_deeply(setting('portctl_by_role')->{r},
    { 'group:synthesized_group_east_1' => ['port:Gi1/2'] }, 'east role');
  is_deeply(setting('host_groups')->{synthesized_group_east_1}, [$OUT], 'east device');
  is_deeply(synth_keys(), ['synthesized_group_east_1'], 'no default tenant groups');

  var tenant => undef;
  load_managed_config();
  is_deeply(setting('portctl_by_role')->{r},
    { 'group:synthesized_group_netdisco_1' => ['port:Gi1/1'] }, 'default role again');
  is_deeply(synth_keys(), ['synthesized_group_netdisco_1'], 'no east groups');
  is($calls->{row_reads}, 2, 'default tenant served from its cache');
};

subtest 'loader__a_failed_read_after_a_load__restores_the_yaml_then_reloads' => sub {
  my $yaml_roles = { y => [$OUT], e => '' };
  yaml(roles => $yaml_roles);
  my $down = 0;
  my $calls = stub_managed_config(
    version => sub { die "database restarting\n" if $down; return 1 },
    rows => { netdisco => { d => { type => 'host_port', maps => [ [[$IN]] ] } } },
  );

  load_managed_config();
  ok(exists setting('portctl_by_role')->{d}, 'd loaded');

  $down = 1;
  load_managed_config();
  ok(!exists setting('portctl_by_role')->{d}, 'd gone');
  is_deeply(setting('portctl_by_role'), normalized($yaml_roles), 'normalized yaml roles');
  is_deeply(synth_keys(), [], 'no synthesized groups');

  $down = 0;
  load_managed_config();
  ok(exists setting('portctl_by_role')->{d}, 'd back');
  is($calls->{row_reads}, 2, 'reloaded, the failure was not cached');
};

subtest 'loader__a_missing_counter_row__counts_as_a_failed_read' => sub {
  my $yaml_roles = { y => [$OUT], e => '' };
  yaml(roles => $yaml_roles);
  stub_managed_config(version => 1, rows => { netdisco => {
    d => { type => 'host_port', maps => [ [[$IN]] ] },
  }});
  load_managed_config();
  ok(exists setting('portctl_by_role')->{d}, 'd loaded');

  stub_managed_config(version => undef, keep_cache => 1);
  eval { load_managed_config(); 1 } or fail("load died: $@");
  is_deeply(setting('portctl_by_role'), normalized($yaml_roles), 'normalized yaml roles');
};

subtest 'loader__each_apply_writes_fresh_hashes' => sub {
  # a job's config override is merged into CONFIG after the apply; the next
  # job's apply must not carry it, even when nothing was reloaded
  yaml(roles => { y => [$OUT] });
  stub_managed_config(version => 1, rows => { netdisco => {} });
  load_managed_config();
  config->{'portctl_by_role'}->{override} = [$IN];
  config->{'host_groups'}->{override} = [$IN];
  load_managed_config();

  ok(!exists setting('portctl_by_role')->{override}, 'role override gone');
  ok(!exists setting('host_groups')->{override}, 'group override gone');
  ok(!exists yaml_setting('portctl_by_role')->{override}, 'clean copy untouched');
};

subtest 'loader__yaml_setting__returns_the_clean_copy' => sub {
  yaml(roles => { y => [$OUT] });
  stub_managed_config(version => 1, rows => { netdisco => {
    dbrole => { type => 'host_port', maps => [ [[$IN]] ] },
  }});
  load_managed_config();
  ok(exists setting('portctl_by_role')->{dbrole}, 'dbrole loaded');

  is_deeply(yaml_setting('portctl_by_role'), { y => [$OUT] }, 'no dbrole in the clean copy');
};

done_testing;
