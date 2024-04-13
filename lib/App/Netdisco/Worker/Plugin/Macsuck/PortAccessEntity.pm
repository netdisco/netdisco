package App::Netdisco::Worker::Plugin::Macsuck::PortAccessEntity;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Worker;
use App::Netdisco::Util::PortAccessEntity qw/update_pae_attributes/;

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return update_pae_attributes($device)
});

true;
