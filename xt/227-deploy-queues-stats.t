#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile updir/;
use FindBin;
use Text::Balanced 'extract_bracketed';

# #1821: netdisco-deploy wrote today's statistics itself, outside any job, so
# the Python version (which only a job's Python worklet knows) became n/a.
# Deploy now queues the stats job, as the Docker images do. This reads the
# source because the script prompts and reaches the network.

my $script = $ENV{ND_DEPLOY_SCRIPT}
  // catfile($FindBin::Bin, updir(), 'bin', 'netdisco-deploy');
open my $fh, '<', $script or die "cannot read $script: $!";
my $source = do { local $/; <$fh> };
close $fh;

sub sub_body {
  my $name = shift;
  return unless $source =~ /^\s*sub\s+\Q$name\E\s*(?=\{)/mg;
  my ($body) = extract_bracketed(substr($source, pos($source)), '{}');
  return $body;
}

our ($queue_ok, @inserted);

package DeployUnderTest {
  use feature 'say';
  sub jq_insert { push @main::inserted, shift; return $main::queue_ok }
  sub color { return '' }
}

my $queue_stats = sub_body('queue_stats');
my $loaded = defined $queue_stats
  && eval "package DeployUnderTest; use feature 'say'; sub queue_stats $queue_stats; 1";
diag $@ if defined $queue_stats and not $loaded;

sub run_queue_stats {
  local $queue_ok = shift;
  @inserted = ();
  my $out = '';
  open my $capture, '>', \$out or die $!;
  my $previous = select $capture;
  my $lived = eval { DeployUnderTest::queue_stats(); 1 };
  select $previous;
  close $capture;
  return ($out, $lived);
}

subtest 'queue_stats__job_queued__inserts_stats_action' => sub {
  ok $loaded, 'bin/netdisco-deploy defines sub queue_stats' or return;
  my ($out) = run_queue_stats(1);
  is scalar @inserted, 1, 'one job queued';
  is_deeply $inserted[0], { action => 'stats' }, 'a stats job';
  like $out, qr/Queued a statistics update for the backend\./;
};

subtest 'queue_stats__queue_fails__warns_and_carries_on' => sub {
  ok $loaded, 'bin/netdisco-deploy defines sub queue_stats' or return;
  my ($out, $lived) = run_queue_stats(0);
  ok $lived, 'does not die';
  like $out, qr/Could not queue a statistics update; the nightly expire job will refresh them\./;
  unlike $out, qr/Queued a statistics update/;
};

subtest 'deploy_db__source__queues_stats_instead_of_computing_them' => sub {
  my $deploy_db = sub_body('deploy_db');
  ok defined $deploy_db, 'bin/netdisco-deploy defines sub deploy_db' or return;
  like $deploy_db, qr/\bqueue_stats\(\)/;
  unlike $deploy_db, qr/update_stats/;
};

subtest 'netdisco_deploy__source__does_not_load_util_statistics' => sub {
  unlike $source, qr/App::Netdisco::Util::Statistics/;
};

done_testing;
