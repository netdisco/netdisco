package App::Netdisco::Daemon::Worker::Poller::Nbtstat;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Core::Nbtstat 'do_nbtstat';
use App::Netdisco::Util::Node 'is_nbtstatable';
use App::Netdisco::Util::Device qw/get_device is_discoverable/;
use App::Netdisco::Daemon::Util ':all';

use NetAddr::IP::Lite ':lower';
use Time::HiRes 'gettimeofday';

use Role::Tiny;
use namespace::clean;

with 'App::Netdisco::Daemon::Worker::Poller::Common';

sub nbtstat_action { \&do_nbtstat }
sub nbtstat_filter { \&is_nbtstatable }
sub nbtstat_layer  { 2 }

sub nbtwalk { (shift)->_walk_body('nbtstat', @_) }

sub nbtstat  {
  my ($self, $job) = @_;

  my $host = NetAddr::IP::Lite->new($job->device);
  my $device = get_device($host->addr);

  unless (is_discoverable($device->ip)) {
      return job_defer("nbtstat deferred: $host is not discoverable");
  }

  # get list of nodes on device
  my $interval = (setting('nbt_max_age') || 7) . ' day';
  my $rs = schema('netdisco')->resultset('NodeIp')->search({
    -bool => 'me.active',
    -bool => 'nodes.active',
    'nodes.switch' => $device->ip,
    'me.time_last' => \[ '>= now() - ?::interval', $interval ],
  },{
    join => 'nodes',
    columns => 'ip',
    distinct => 1,
  })->ip_version(4);

  my @nodes = $rs->get_column('ip')->all;
  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';

  $self->_single_node_body('nbtstat', $_, $now)
    for @nodes;

  return job_done("Ended nbtstat for ". $host->addr);
}

1;
