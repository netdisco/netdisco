#!/usr/bin/env perl

use strict; use warnings;
no warnings 'once';

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB;
use App::Netdisco::Backend::Job;
use App::Netdisco::Worker::Plugin::Discover::Properties::Tags ();

use Try::Tiny;
use Dancer qw/:moose :script !pass/;

# Discover upserts device_port instead of recreating it, so the port tags
# worker must clear tags on ports that no longer match. The DBIC searches are
# recorded with their SQL, so no database is needed.

my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

config->{'device_auth'} = [{driver => 'snmp'}];

package RecordingRows;
our (@writes, @clears);
sub new { my ($class, $real, $is_clear) = @_; return bless { real => $real, clear => $is_clear }, $class }
sub update {
  my ($self, $set) = @_;
  my ($sql, @bind) = @{ ${ $self->{real}->as_query } };
  push @{ $self->{clear} ? \@clears : \@writes }, { set => $set, sql => $sql, bind => \@bind };
  return $self->{clear} ? 3 : 1;
}

package RecordingSchema;
# an offline PostgreSQL schema, so as_query builds the real SQL without a connection
our $offline = do {
  local $SIG{__WARN__} = sub { warn @_ unless $_[0] =~ /unversioned/ };
  my $schema = App::Netdisco::DB->clone;
  $schema->storage_type('::DBI::Pg');
  $schema->connection('dbi:Pg:dbname=netdisco_xt_offline;host=127.0.0.1;port=1');
  $schema;
};
sub resultset {
  my ($self, $name) = @_;
  return bless { real => $offline->resultset($name) }, 'RecordingResultSet';
}

package RecordingResultSet;
sub search {
  my ($self, $cond, $attrs) = @_;
  return RecordingRows->new($self->{real}->search_rs($cond, $attrs), !$attrs);
}

package main;

no warnings 'redefine';
*App::Netdisco::Worker::Plugin::Discover::Properties::Tags::schema
  = sub { return bless {}, 'RecordingSchema' };

# register_worker stores the wrapped subs by action, phase, namespace and priority
my $port_tag_worker = (grep { 1 } @{ vars->{'workers'}{'discover'}{'main'}{'properties'}{0} })[1];

my $ADDRESS = '192.0.2.1';

sub run_tags {
  my ($tag_setting, $ports) = @_;
  @RecordingRows::writes = @RecordingRows::clears = ();
  delete @{ vars() }{qw/hook_data timestamp/};
  vars->{'hook_data'} = { ports => $ports } if $ports;
  local config->{'tags'} = $tag_setting;

  my $device = App::Netdisco::DB->resultset('Device')->new_result({ ip => $ADDRESS });
  $device->in_storage(1);
  my $job = App::Netdisco::Backend::Job->new({
    job => 0, device => $device, action => 'discover::properties',
  });
  try { $port_tag_worker->($job) }
  catch { diag "worker died: $_"; $job->status("error") };
  return $job;
}

my $matches_gi1 = { device_port => { access => { 'ip:192.0.2.1' => 'port:Gi0/1' } } };
my @ports = ({ port => 'Gi0/1' }, { port => 'Gi0/2' });

subtest 'port_tags__port_stops_matching__tags_written_empty' => sub {
  run_tags($matches_gi1, [ @ports ]);
  is scalar @RecordingRows::clears, 1, 'one clear';
  my $clear = $RecordingRows::clears[0];
  is_deeply $clear->{set}, { tags => '{}' }, 'tags set to the empty array';
  like $clear->{sql}, qr/\bNOT IN\b/i, 'outside the matched set';
  like $clear->{sql}, qr/WHERE .*\bip = \?/, 'scoped to the device';
  is_deeply [ map { $_->[1] } grep { $_->[0]{dbic_colname} eq 'ip' } @{ $clear->{bind} } ],
    [$ADDRESS], 'the device ip is bound';
  ok scalar(grep { $_ eq 'Gi0/1' } map { $_->[1] } @{ $clear->{bind} }), 'matched port is in the exclusion list'
    or diag explain $clear;
  is scalar @RecordingRows::writes, 1, 'the matching port is still tagged';
};

subtest 'port_tags__map_emptied__all_tagged_ports_cleared' => sub {
  run_tags({ device_port => {} }, [ @ports ]);
  is scalar @RecordingRows::writes, 0, 'nothing tagged';
  is scalar @RecordingRows::clears, 1, 'one clear';
  my $clear = $RecordingRows::clears[0];
  is_deeply $clear->{set}, { tags => '{}' };
  like $clear->{sql}, qr/WHERE .*\bip = \?/, 'scoped to the device';
  like $clear->{sql}, qr/\b1=1\b/, 'no port is kept';
  unlike $clear->{sql}, qr/\bNOT IN\b/i, 'no port exclusion list';
  is_deeply [ map { $_->[1] } grep { $_->[0]{dbic_colname} eq 'ip' } @{ $clear->{bind} } ],
    [$ADDRESS], 'the device ip is bound';
};

subtest 'port_tags__config_not_a_hash__all_tagged_ports_cleared' => sub {
  foreach my $setting (undef, 'junk', [ 1 ], { device_port => 'junk' }, { device => {} }) {
    run_tags($setting, [ @ports ]);
    is scalar @RecordingRows::clears, 1, 'one clear for ' . (defined $setting ? ref($setting) || $setting : 'undef');
  }
};

subtest 'port_tags__untagged_port__not_written' => sub {
  run_tags($matches_gi1, [ @ports ]);
  like $RecordingRows::clears[0]{sql}, qr/tags\s*!=|tags\s*<>/i, 'only rows with non-empty tags';
  my @binds = map { $_->[1] } @{ $RecordingRows::clears[0]{bind} };
  ok scalar(grep { $_ eq '{}' } @binds), 'compared with the empty array';
};

subtest 'port_tags__ports_list_absent__clears_nothing' => sub {
  run_tags($matches_gi1, undef);
  is scalar @RecordingRows::clears, 0, 'no clear';
  is scalar @RecordingRows::writes, 0, 'no write';
  run_tags({ device_port => {} }, undef);
  is scalar @RecordingRows::clears, 0, 'no clear when nothing is configured either';
};

subtest 'port_tags__device_has_no_ports__clears_all_tagged_ports' => sub {
  run_tags($matches_gi1, []);
  is scalar @RecordingRows::clears, 1, 'one clear';
};

done_testing;
