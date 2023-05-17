package App::Netdisco::Worker::Plugin::Delete::Hooks;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Worker;
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;

register_worker({ phase => 'late' }, sub {
  my ($job, $workerconf) = @_;
  my $count = 0;

  my $best = $job->best_status;
  if (Status->$best->level != Status->done->level) {
      return Status
        ->info(sprintf ' [%s] hooks - skipping due to incomplete job', $job->device);
  }

  foreach my $conf (@{ setting('hooks') }) {
    my $no   = ($conf->{'filter'}->{'no'}   || []);
    my $only = ($conf->{'filter'}->{'only'} || []);

    next if acl_matches( $job->device, $no );
    next unless acl_matches_only( $job->device, $only);

    if ($conf->{'event'} eq 'delete') {
      $count += queue_hook('delete', $conf);
      debug sprintf ' [%s] hooks - %s queued', 'delete', $job->device;
    }
  }

  return Status
    ->info(sprintf ' [%s] hooks - %d queued', $job->device, $count);
});

true;
