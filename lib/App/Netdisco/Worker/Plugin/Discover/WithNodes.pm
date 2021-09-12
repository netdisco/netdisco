package App::Netdisco::Worker::Plugin::Discover::WithNodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # if requested, and the device has not yet been
  # arpniped/macsucked, queue those jobs now
  return unless $device->in_storage and $job->subaction eq 'with-nodes';

  if (!defined $device->last_macsuck and $device->has_layer(2)) {
    jq_insert({
      device => $device->ip,
      action => 'macsuck',
      username => $job->username,
      userip => $job->userip,
    });
  }

  if (!defined $device->last_arpnip and $device->has_layer(3)) {
    jq_insert({
      device => $device->ip,
      action => 'arpnip',
      username => $job->username,
      userip => $job->userip,
    });
  }

  return Status->info("Queued macsuck and arpnip for $device.");
});

true;
