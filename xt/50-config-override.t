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
use Dancer qw/:moose :script !pass/;

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# configure logging to force console output
my $CONFIG = config();
$CONFIG->{logger} = 'console';
$CONFIG->{log} = ($ENV{'DANCER_DEBUG'} ? 'debug' : 'error');
Dancer::Logger->init('console', $CONFIG);

# when ND2_DO_QUIET active, log is JSON, this returns Perl struct
{
  package App::Netdisco::Backend::Job;
  use JSON::XS ();
  sub log_struct { return JSON::XS::decode_json((shift)->log) };
}

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

# runs a dumpconfig job
# sets ND2_DO_QUIET so that JSON encoded result is logged
# can get and decode the job log to check results
# or still inspect fields of the Job instance such as subaction or port

# pass the subaction and port values in first and second param
# for dumpconfig, the port value is an override for the config key to dump

# returns the Job instance

sub run_dumpconfig_for {
  my ($extra, $print_this_instead) = @_;

  my $job = App::Netdisco::Backend::Job->new({
    job => 0,
    device => App::Netdisco::DB->resultset('Device')->new_result({ip => '192.0.2.1'}),
    action => 'dumpconfig',
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
    print STDERR "error running job: $_";  
    $job->log("error running job: $_");
  };
  $ENV{ND2_DO_QUIET} = $quiet;

  return $job;
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# clear user device_auth and set our own with two tags
config->{'device_auth'} = [{tag => 'foo', driver => 'snmp'}, {tag => 'bar', driver => 'cli'}];

my $j1 = run_dumpconfig_for('device_auth');
is($j1->status, 'done', 'status is done');
is_deeply($j1->log_struct, [{tag => 'foo', driver => 'snmp'}, {tag => 'bar', driver => 'cli'}],
  'tested that dumpconfig device_auth to json works');

=over 4
=item * C<undef> (changed to empty string if subaction)
=cut

$j1 = run_dumpconfig_for();
is_deeply($j1->subaction, q{}, "undefined subaction is promoted to empty string");

=over 4
=item * C<"">
=cut

$j1 = run_dumpconfig_for(q{});
is_deeply($j1->subaction, q{}, "empty string subaction is unchanged");

=over 4
=item * C<"unchanged">
=cut

$j1 = run_dumpconfig_for(q{unchanged});
is_deeply($j1->subaction, q{unchanged}, "string subaction is unchanged");

=over 4
=item * C<'"unchanged"'>
=cut

$j1 = run_dumpconfig_for(q{"parsed"});
is_deeply($j1->subaction, q{parsed}, "JSON string subaction is parsed");

=over 4
=item * C<[{"mac": "string", "port": "string"}]>
=cut

$j1 = run_dumpconfig_for([{"mac" => "string", "port" => "string"}]);
is_deeply($j1->subaction, [{"mac" => "string", "port" => "string"}], "Perl array is unchanged");

=over 4
=item * C<{"mac": "string", "port": "string"}> (unsupported)
=cut

$j1 = run_dumpconfig_for({"mac" => "string", "port" => "string"});
is_deeply($j1->subaction, q{}, "Perl hash is unsupported (consumed)");

=over 4
=item * C<{"value": [{"mac": "string", "port": "string"}]}>
=cut

$j1 = run_dumpconfig_for({value => [{"mac" => "string", "port" => "string"}]});
is_deeply($j1->subaction, [{"mac" => "string", "port" => "string"}], "Perl array VALUE is unchanged");

=over 4
=item * C<{"value": {"mac": "string", "port": "string"}}>
=cut

$j1 = run_dumpconfig_for({value => {"mac" => "string", "port" => "string"}});
is_deeply($j1->subaction, {"mac" => "string", "port" => "string"}, "Perl hash VALUE is unchanged");

=over 4
=item * C<{"value": '{"mac": "string", "port": "string"}'}>
=cut

$j1 = run_dumpconfig_for({value => '{"mac": "string", "port": "string"}'});
is_deeply(from_json($j1->subaction), {"mac" => "string", "port" => "string"}, "JSON dict VALUE is supported");

=over 4
=item * C<{"value": "unchanged", "with": {"snmptimeout": 4000000}}>
=cut

$j1 = run_dumpconfig_for({value => 'unchanged', with => {snmptimeout => 4000000}}, 'snmptimeout');
is_deeply($j1->subaction, 'unchanged', "composite has unchanged text VALUE");
is_deeply(from_json($j1->log), 4000000, "Perl hash WITH sets config");

=over 4
=item * C<{"value": "unchanged", "with": '{"snmptimeout": 5000000}'}>
=cut

$j1 = run_dumpconfig_for({value => 'unchanged', with => '{"snmptimeout": 5000000}'}, 'snmptimeout');
is_deeply(from_json($j1->log), 5000000, "JSON dict WITH sets config");

=over 4
=item * C<{"value": "unchanged", "with": 'snmptimeout=6000000'}>
=cut

$j1 = run_dumpconfig_for({value => 'unchanged', with => 'snmptimeout=6000000'}, 'snmptimeout');
is_deeply(from_json($j1->log), 6000000, "k=v WITH sets config");

=over 4
=item * C<{"snmptimeout": 7000000}>
=cut

$j1 = run_dumpconfig_for({snmptimeout => 7000000}, 'snmptimeout');
is_deeply(from_json($j1->log), 7000000, "subaction perl hash sets config");

=over 4
=item * C<'{"snmptimeout": 8000000}'>
=cut

$j1 = run_dumpconfig_for('{"snmptimeout": 8000000}', 'snmptimeout');
is_deeply(from_json($j1->log), 8000000, "subaction JSON dict sets config");

=over 4
=item * C<snmptimeout=9000000>
=cut

$j1 = run_dumpconfig_for('snmptimeout=9000000', 'snmptimeout');
is_deeply(from_json($j1->log), 9000000, "subaction k=v sets config");

=over 4
=item * C<{"value": "unchanged", "with": "FAILS"}> (unsupported)
=cut

$j1 = run_dumpconfig_for({"value" => "unchanged", "with" => "FAILS"});
is_deeply($j1->subaction, 'unchanged', "string WITH is ignored and does not change VALUE");

=over 4
=item * C<{"value": "unchanged", "with": ["FAILS"]}> (unsupported)
=cut

$j1 = run_dumpconfig_for({"value" => "unchanged", "with" => ["FAILS"]});
is_deeply($j1->subaction, 'unchanged', "array WITH is ignored and does not change VALUE");

done_testing;