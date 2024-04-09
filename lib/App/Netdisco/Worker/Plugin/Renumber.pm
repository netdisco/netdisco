package App::Netdisco::Worker::Plugin::Renumber;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use NetAddr::IP qw/:rfc3021 :lower/;
use App::Netdisco::Util::Device qw/get_device renumber_device/;

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $extra) = map {$job->$_} qw/device port extra/;

  return Status->error('Missing device (-d).')
    unless defined $device;

  if (! $device->in_storage) {
      return Status->error(sprintf "unknown device: %s.", $device);
  }

  my $new_ip = NetAddr::IP->new($extra);
  unless ($new_ip and $new_ip->addr ne '0.0.0.0') {
      return Status->error("bad host or IP: ".($extra || '0.0.0.0'));
  }

  debug sprintf 'renumber - from IP: %s', $device;
  debug sprintf 'renumber -   to IP: %s (param: %s)', $new_ip->addr, $extra;

  if ($new_ip->addr eq $device->ip) {
      return Status->error('old and new are the same device (use device_identity instead).');
  }

  my $new_dev = get_device($new_ip->addr);
  if ($new_dev and $new_dev->in_storage and ($new_ip->addr ne $device->ip)) {
      return Status->error(sprintf "already know new device as: %s (use device_identity instead).", $new_dev->ip);
  }

  return Status->done('Renumber is able to run');
});

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $extra) = map {$job->$_} qw/device port extra/;

  my $old_ip = $device->ip;
  my $new_ip = NetAddr::IP->new($extra);

  renumber_device($device, $new_ip);
  return Status->done(sprintf 'Renumbered device %s to %s (%s).',
    $old_ip, $new_ip, ($device->dns || ''));
});

true;
