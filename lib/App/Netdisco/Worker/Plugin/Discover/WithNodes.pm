package App::Netdisco::Worker::Plugin::Discover::WithNodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';
use App::Netdisco::Util::Permission 'acl_matches';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # if requested, and the device has not yet been
  # arpniped/macsucked, queue those jobs now
  return unless $device->in_storage and $job->subaction eq 'with-nodes';

  if (!defined $device->last_macsuck and ($device->has_layer(2)
                                          or acl_matches($device, 'force_macsuck')
                                          or acl_matches($device, 'ignore_layers'))) {
    jq_insert({
      device => $device->ip,
      action => 'macsuck',
      username => $job->username,
      userip => $job->userip,
    });
    debug sprintf ' [%s] queued macsuck', $device;
  }

  if (!defined $device->last_arpnip and ($device->has_layer(3)
                                         or acl_matches($device, 'force_arpnip')
                                         or acl_matches($device, 'ignore_layers'))) {
    jq_insert({
      device => $device->ip,
      action => 'arpnip',
      username => $job->username,
      userip => $job->userip,
    });
    debug sprintf ' [%s] queued arpnip', $device;
  }
});

true;
