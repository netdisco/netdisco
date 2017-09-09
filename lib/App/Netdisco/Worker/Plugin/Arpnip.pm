package App::Netdisco::Worker::Plugin::Arpnip;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_arpnipable_now';
use App::Netdisco::Transport::SNMP ();

register_worker({ primary => true }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->error('arpnip failed: unable to interpret device param')
    unless defined $device;

  my $host = $device->ip;

  return Status->done("arpnip skipped: $host not yet discovered")
    unless $device->in_storage;

  return Status->defer("arpnip skipped: $host is pseudo-device")
    if $device->vendor and $device->vendor eq 'netdisco';

  return Status->defer("arpnip deferred: $host is not arpnipable")
    unless is_arpnipable_now($device);

  return Status->done('Arpnip is able to run.');
});

true;
