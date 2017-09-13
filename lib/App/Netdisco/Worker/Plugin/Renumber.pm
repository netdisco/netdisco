package App::Netdisco::Worker::Plugin::Renumber;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use NetAddr::IP qw/:rfc3021 :lower/;
use App::Netdisco::Util::Device qw/get_device renumber_device/;

register_worker({ stage => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $extra) = map {$job->$_} qw/device port extra/;
  return Status->error('Missing device (-d).') if !defined $device;
  my $old_ip = $device->ip;

  my $new_ip = NetAddr::IP->new($extra);
  unless ($new_ip and $new_ip->addr ne '0.0.0.0') {
      return Status->error("Bad host or IP: ".($extra || '0.0.0.0'));
  }

  my $new_dev = get_device($new_ip->addr);
  if ($new_dev and $new_dev->in_storage and ($new_dev->ip ne $device->ip)) {
      return Status->error(sprintf "Already know new device as: %s.", $new_dev->ip);
  }

  renumber_device($device, $new_ip);
  return Status->done(sprintf 'Renumbered device %s to %s (%s).',
    $device->ip, $new_ip, ($device->dns || ''));
});

true;
