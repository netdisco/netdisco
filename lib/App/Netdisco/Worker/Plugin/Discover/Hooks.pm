package App::Netdisco::Worker::Plugin::Discover::Hooks;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Worker;
use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;

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

    next if check_acl_no( $job->device, $no );
    next unless check_acl_only( $job->device, $only);

    if (vars->{'new_device'} and $conf->{'event'} eq 'new_device') {
      $count += queue_hook('new_device', $conf);
      debug sprintf ' [%s] hooks - %s queued', 'new_device', $job->device;
    }

    if ($conf->{'event'} eq 'discover') {
      $count += queue_hook('discover', $conf);
      debug sprintf ' [%s] hooks - %s queued', 'discover', $job->device;
    }
  }

  return Status
    ->info(sprintf ' [%s] hooks - %d queued', $job->device, $count);
});

true;
