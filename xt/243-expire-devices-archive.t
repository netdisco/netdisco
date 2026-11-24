#!/usr/bin/env perl

# expire_devices queued its delete jobs without the archive flag, so an
# expired device lost all its node, node_ip and node_nbt rows, its MAC
# history, where a delete from the UI with "Archive Nodes" keeps them
# inactive for expire_nodes_archive to age out. expire_devices_archive sets
# that flag on the jobs expire queues. There is no database in CI, so this
# runs the real expire and delete workers against stubs.
#
# Claims, kept apart:
#   - off (the default), the delete job carries no archive flag, as before;
#   - on, it carries port 1, the flag the UI and API set;
#   - port 1 is not read as a configuration override;
#   - the delete worker passes the flag to delete_device as archive.

use strict;
use warnings;
no warnings 'once';

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::Backend::Job;
use App::Netdisco::Worker::Plugin::Expire ();
use App::Netdisco::Worker::Plugin::Delete ();

use Dancer qw/:moose :script !pass/;

config->{logger} = 'null';

ok !setting('expire_devices_archive'),
  'expireArchive__default__off';

my @queued;

package FakeRS;
sub new { bless {}, shift }
sub search { $_[0] }
sub get_column { $_[0] }
sub all { ('192.0.2.1') }
sub create { 1 }
sub delete { 0 }

package FakeSchema;
sub new { bless {}, shift }
sub txn_do { my ($self, $code) = @_; return $code->() }
sub resultset { FakeRS->new }

package main;

{
  no warnings 'redefine';
  *App::Netdisco::Worker::Plugin::Expire::schema = sub { FakeSchema->new };
  *App::Netdisco::Worker::Plugin::Expire::update_stats = sub { 1 };
  *App::Netdisco::Worker::Plugin::Expire::ipv4_from_hostname = sub { '127.0.0.1' };
  *App::Netdisco::Worker::Plugin::Expire::jq_insert = sub { push @queued, @{ $_[0] } };
}

my ($expire) = grep { ref }
  @{ vars->{'workers'}{'expire'}{'main'}{'_base_'}{0} || [] };

sub run_expire {
  my $archive = shift;
  config->{$_} = 0 for qw/expire_nodes expire_nodes_archive
                          expire_nodeip_orphans expire_jobs expire_userlog/;
  config->{expire_devices} = { 'group:__ANY__' => 60 };
  config->{expire_devices_archive} = $archive;
  @queued = ();
  $expire->(App::Netdisco::Backend::Job->new({ job => 0, action => 'expire' }));
  return [ grep { $_->{action} eq 'delete' } @queued ];
}

my $off = run_expire(0);
is scalar @$off, 1, 'expireArchive__off__queues_the_delete';
ok !$off->[0]{port}, 'expireArchive__off__no_archive_flag';

my $on = run_expire(1);
is scalar @$on, 1, 'expireArchive__on__queues_the_delete';
is $on->[0]{port}, 1, 'expireArchive__on__archive_flag_set';

ok !App::Netdisco::Backend::Job->carries_config_overrides($on->[0]),
  'expireArchive__flag__not_a_config_override';

# the delete worker, with the device and delete_device replaced
my @archive;
{
  package FakeDevice;
  use overload '""' => sub { '192.0.2.1' }, fallback => 1;
  sub new { bless {}, shift }
  sub in_storage { 1 }
  sub get_columns { (ip => '192.0.2.1') }
}
{
  no warnings 'redefine';
  *App::Netdisco::Worker::Plugin::Delete::delete_device = sub { push @archive, $_[1]; 1 };
}
my ($delete) = grep { ref }
  @{ vars->{'workers'}{'delete'}{'main'}{'_base_'}{0} || [] };

{
  package FakeJob;
  our @ISA = ('App::Netdisco::Backend::Job');
  sub device { FakeDevice->new }
}
$delete->(FakeJob->new({ job => 0, action => 'delete', port => $on->[0]{port} }));
$delete->(FakeJob->new({ job => 0, action => 'delete', port => $off->[0]{port} }));
is_deeply \@archive, [1, 0], 'expireArchive__delete__passes_flag_as_archive';

done_testing;
