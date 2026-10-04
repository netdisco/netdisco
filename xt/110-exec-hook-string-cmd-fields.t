#!/usr/bin/env perl

# The shipped exec hooks are string form and use only ip and ndo.

use strict;
use warnings;

BEGIN {
  $ENV{DANCER_ENVDIR} = '/dev/null';
  $ENV{NETDISCO_DO} = '/bin/echo';
}

use Test::More 0.88;
use Test::File::ShareDir::Dist { 'App-Netdisco' => 'share/' };

use App::Netdisco;
use App::Netdisco::Backend::Job;

use Dancer qw/:moose :script !pass/;
use Encode 'encode';
use File::Slurper 'read_text';
use File::Temp 'tempdir';
use MIME::Base64 'encode_base64';

config->{logger} = 'null';

{
  package MyWorker;
  use Moo;
  with 'App::Netdisco::Worker::Runner';
}

my $dir = tempdir(CLEANUP => 1);
my $canary = "$dir/canary";
my $out = "$dir/out";
my $hostile_name = "; touch $canary";

sub run_hook {
  my ($cmd, $event_data) = @_;
  my $extra = { action_conf => { cmd => $cmd, event => 'discover' },
                event_data  => $event_data };
  my $job = App::Netdisco::Backend::Job->new({
    job => 0,
    action => 'hook::exec',
    subaction => encode_base64( encode('UTF-8', to_json($extra)), '' ),
  });
  MyWorker->new()->run($job);
  return $job;
}

subtest 'execHook__string_cmd_naming_a_free_text_field__fails_before_the_shell' => sub {
  my $job = run_hook('/bin/echo [% name %]',
    { ip => '192.0.2.1', name => $hostile_name });
  is $job->status, 'error', 'the hook job fails';
  like $job->log, qr/undefined variable: name/, 'the log names the field';
  like $job->log, qr/list/, 'and the list form as the remedy';
  ok !-e $canary, 'nothing ran';
};

subtest 'execHook__list_cmd_naming_a_free_text_field__passes_it_as_one_argument' => sub {
  my $job = run_hook(
    ['/bin/sh', '-c', 'printf %s "$1" > '. $out, 'sh', '[% name %]'],
    { ip => '192.0.2.1', name => $hostile_name });
  is $job->status, 'done', 'the hook job runs';
  is read_text($out), $hostile_name, 'the field arrives verbatim';
  ok !-e $canary, 'and is never parsed by the shell';
};

subtest 'execHook__string_cmd_in_the_shipped_shape__still_runs_through_the_shell' => sub {
  unlink $out;
  my $job = run_hook(q{[% ndo %] '[% ip %]' | /bin/cat > }. $out,
    { ip => '192.0.2.1', name => $hostile_name });
  is $job->status, 'done', 'the hook job runs';
  is read_text($out), "192.0.2.1\n", 'with ndo and ip substituted';
  ok !-e $canary, 'and the unreferenced field is inert';
};

done_testing;
