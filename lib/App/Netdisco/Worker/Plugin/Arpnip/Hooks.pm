package App::Netdisco::Worker::Plugin::Arpnip::Hooks;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Worker;
use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;

register_worker({ phase => 'late' }, sub {
  my ($job, $workerconf) = @_;
  my $count = 0;

  foreach my $conf (@{ setting('hooks') }) {
    my $no   = ($conf->{'filter'}->{'no'}   || []);
    my $only = ($conf->{'filter'}->{'only'} || []);

    next if check_acl_no( $job->device, $no );
    next unless check_acl_only( $job->device, $only);

    if ($conf->{'event'} eq 'arpnip') {
      $count += queue_hook('arpnip', $conf);
      debug sprintf ' [%s] hooks - %s queued', 'arpnip', $job->device;
    }
  }

  return Status
    ->info(sprintf ' [%s] hooks - %d queued', $job->device, $count);
});

true;
