package App::Netdisco::Worker::Plugin::Discover::Hooks;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Worker;

register_worker({ phase => 'late' }, sub {
  my ($job, $workerconf) = @_;
  my $count = 0;

  foreach my $conf (@{ setting('hooks') }) {
    $count += queue_hook('new_device', $conf)
      if vars->{'new_device'} and $conf->{'event'} eq 'new_device';

    if ($conf->{'event'} eq 'discover') {
      # TODO filter for no/only
      my $no   = ($conf->{'filter'}->{'no'}   || '');
      my $only = ($conf->{'filter'}->{'only'} || '');
      my $when = ($conf->{'filter'}->{'when'} || '');

      $count += queue_hook('discover', $conf);
    }
  }

  return Status->info(sprintf ' [%s] hooks - %d queued', $job->device, $count);
});

true;
