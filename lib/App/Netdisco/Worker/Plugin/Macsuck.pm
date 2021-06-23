package App::Netdisco::Worker::Plugin::Macsuck;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_macsuckable_now';

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->error('macsuck failed: unable to interpret device param')
    unless defined $device;

  return Status->error("macsuck skipped: $device not yet discovered")
    unless $device->in_storage;

  return Status->info("macsuck skipped: $device is not macsuckable")
    unless is_macsuckable_now($device);

  # support for Hooks
  vars->{'hook_data'} = { $device->get_columns };
  delete vars->{'hook_data'}->{'snmp_comm'}; # for privacy

  return Status->done('Macsuck is able to run.');
});

true;
