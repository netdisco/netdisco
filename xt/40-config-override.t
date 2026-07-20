#!/usr/bin/env perl

use strict; use warnings;

BEGIN { $ENV{DANCER_ENVDIR} = '/dev/null'; }

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use lib 'xt/lib';

use App::Netdisco;
use App::Netdisco::DB; # fake device row
use App::Netdisco::Backend::Job;

use Try::Tiny;
use Data::Compare;
use Dancer qw/:moose :script !pass/;

# configure logging to force console output
my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

sub do_job {
  my ($pkg, $extra, $print_this_instead) = @_;

  my $job = App::Netdisco::Backend::Job->new({
    job => 0,
    device => App::Netdisco::DB->resultset('Device')->new_result({ip => '192.0.2.1'}),
    action => lc($pkg),
    subaction => $extra,
    port => $print_this_instead,
  });

  my $quiet = $ENV{ND2_DO_QUIET};
  $ENV{ND2_DO_QUIET} = 1;
  try {
    #info sprintf 'test: started at %s', scalar localtime;
    MyWorker->new()->run($job);
    #info sprintf 'test: %s: %s', $job->status, $job->log;
  }
  catch {
    $job->status('error');
    $job->log("error running job: $_");
  };
  $ENV{ND2_DO_QUIET} = $quiet;

  return $job;
}

# clear user device_auth and set our own
config->{'device_auth'} = [{tag => 'foo', driver => 'snmp'}, {tag => 'bar', driver => 'cli'}];

my $j1 = do_job('dumpconfig', 'device_auth');
is($j1->status, 'done', 'status is done');
is_deeply(from_json($j1->log), [{tag => 'foo', driver => 'snmp'}, {tag => 'bar', driver => 'cli'}],
  'tested that dumpconfig device_auth to json works');

# TESTS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# -e yes   
# NETDISCO_WITH_CONFIGURATION=yes

is_deeply(from_json(do_job('dumpconfig', 'yes', 'device_auth_tag_hint')->log), "yes",
  'tested -e yes');

# -e to_json({"value": "yes", "with": {"snmptimeout": 3000000}})
# NETDISCO_WITH_CONFIGURATION=to_json({"value": "yes", "with": {"snmptimeout": 3000000}})

is_deeply(from_json(do_job('dumpconfig',
    {"value" => "yes", "with" => {"snmptimeout"=> 3000000}},
    'device_auth_tag_hint')->log),
  "yes",
  'tested -e {"value": "yes", "with": {"snmptimeout": 3000000}} / device_auth_tag_hint is yes');

is_deeply(from_json(do_job('dumpconfig',
    {"value" => "yes", "with" => {"snmptimeout"=> 3000000}},
    'snmptimeout')->log),
  3000000,
  'tested -e {"value": "yes", "with": {"snmptimeout": 3000000}} / snmptimeout is 3000000');

# -e to_json({"value": "yes", "with": "my_deviceauth_tag"})
# NETDISCO_WITH_CONFIGURATION=to_json({"value": "yes", "with": "my_deviceauth_tag"})

is_deeply(do_job('dumpconfig',
    {"value" => "yes", "with" => "my_deviceauth_tag"})->subaction,
  "yes",
  'tested -e {"value": "yes", "with": "my_deviceauth_tag"} / subaction is yes');

is_deeply(from_json(do_job('dumpconfig',
    {"value" => "yes", "with" => "my_deviceauth_tag"},
    'device_auth_tag_hint')->log),
  "my_deviceauth_tag",
  'tested -e {"value": "yes", "with": "my_deviceauth_tag"} / device_auth_tag_hint is my_deviceauth_tag');

# -e to_json([{"ip": "31.133.156.36", "mac": "50:28:4a:0b:24:71"}])
# NETDISCO_WITH_CONFIGURATION=to_json([{"ip": "31.133.156.36", "mac": "50:28:4a:0b:24:71"}])

is_deeply(do_job('dumpconfig',
    [{"ip" => "31.133.156.36", "mac" => "50:28:4a:0b:24:71"}])->subaction,
  [{"ip" => "31.133.156.36", "mac" => "50:28:4a:0b:24:71"}],
  'tested -e [{"ip": "31.133.156.36", "mac": "50:28:4a:0b:24:71"}] / subaction is the array');

# -e to_json({"value": [{"ip": "31.133.156.36", "mac": "50:28:4a:0b:24:71"}], "with": "my_deviceauth_tag"})
# NETDISCO_WITH_CONFIGURATION=to_json({"value": [{"ip": "31.133.156.36", "mac": "50:28:4a:0b:24:71"}], "with": "my_deviceauth_tag"})

#is_deeply(do_job('dumpconfig',
#    {"value" => [{"ip" => "31.133.156.36", "mac" => "50:28:4a:0b:24:71"}], "with" => "my_deviceauth_tag"})->subaction,
#  to_json([{"mac" => "50:28:4a:0b:24:71", "ip" => "31.133.156.36"}]),
#  'tested -e {"value": [{"ip": "31.133.156.36", "mac": "50:28:4a:0b:24:71"}], "with": "my_deviceauth_tag"} / with subaction is the array');

is_deeply(from_json(do_job('dumpconfig',
    {"value" => [{"ip" => "31.133.156.36", "mac" => "50:28:4a:0b:24:71"}], "with" => "my_deviceauth_tag"},
    'device_auth_tag_hint')->log),
  "my_deviceauth_tag",
  'tested -e {"value": [{"ip": "31.133.156.36", "mac": "50:28:4a:0b:24:71"}], "with": "my_deviceauth_tag"} / device_auth_tag_hint is my_deviceauth_tag');

# -e '{"value": "[{\"ip\": \"31.133.156.36\", \"mac\": \"50:28:4a:0b:24:71\"}]", "with": "my_deviceauth_tag"}'
# NETDISCO_WITH_CONFIGURATION='{"value": "[{\"ip\": \"31.133.156.36\", \"mac\": \"50:28:4a:0b:24:71\"}]", "with": "my_deviceauth_tag"}'

is_deeply(from_json(do_job('dumpconfig',
    '{"value": "[{\"ip\": \"31.133.156.36\", \"mac\": \"50:28:4a:0b:24:71\"}]", "with": "my_deviceauth_tag"}',
    'device_auth_tag_hint')->log),
  "my_deviceauth_tag",
  'tested -e \'{"value": "[{\"ip\": \"31.133.156.36\", \"mac\": \"50:28:4a:0b:24:71\"}]", "with": "my_deviceauth_tag"}\' / pure text json');

# -e to_json({"snmptimeout": 3000000})
# NETDISCO_WITH_CONFIGURATION=to_json({"snmptimeout": 3000000})

is_deeply(from_json(do_job('dumpconfig',
    {"snmptimeout" => 12345678},
    'snmptimeout')->log),
  12345678,
  'tested -e {"snmptimeout" => 12345678} / snmptimeout');

# -e "snmptimeout=3000000"
# NETDISCO_WITH_CONFIGURATION="snmptimeout=3000000"

is_deeply(from_json(do_job('dumpconfig',
    "snmptimeout=12345678",
    'snmptimeout')->log),
  12345678,
  'tested -e "snmptimeout=12345678" / k=v snmptimeout');

# -e "snmptimeout=3000000,skip_neighbor_queue=true"
# NETDISCO_WITH_CONFIGURATION="snmptimeout=3000000,skip_neighbor_queue=true"

is_deeply(from_json(do_job('dumpconfig',
    "snmptimeout=3000000,skip_neighbor_queue=true",
    'skip_neighbor_queue')->log),
  'true',
  'tested -e "snmptimeout=3000000,skip_neighbor_queue=true" / skip_neighbor_queue=true');

# -e to_json({"with": "my_deviceauth_tag"})
# NETDISCO_WITH_CONFIGURATION=to_json({"with": "my_deviceauth_tag"})

is_deeply(from_json(do_job('dumpconfig',
    {"with" => "my_deviceauth_tag"},
    'device_auth_tag_hint')->log),
  "my_deviceauth_tag",
  'tested -e {"with": "my_deviceauth_tag"} / only with device_auth_tag_hint');

done_testing;

# TESTS ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

