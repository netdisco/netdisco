package App::Netdisco::Worker::Plugin::Macsuck::PortAccessEntity;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';
use Data::Dumper;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Worker;
use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;
use App::Netdisco::Util::PortAccessEntity qw/update_pae_attributes/;

register_worker({ phase => 'main', driver => 'snmp' }, sub {

  my ($job, $workerconf) = @_;
  my $device = $job->device;
  return update_pae_attributes($device)

});

true;
