package App::Netdisco::Backend::Worker::Poller::Nbtstat;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Core::Nbtstat qw/nbtstat_resolve_async store_nbt/;
use App::Netdisco::Util::Node 'is_nbtstatable';
use App::Netdisco::Util::Device qw/get_device is_macsuckable/;
use App::Netdisco::Backend::Util ':all';

use NetAddr::IP::Lite ':lower';
use Time::HiRes 'gettimeofday';

use Role::Tiny;
use namespace::clean;

with 'App::Netdisco::Backend::Worker::Poller::Common';

sub nbtstat_action { \&do_nbtstat }
sub nbtstat_filter { \&is_nbtstatable }
sub nbtstat_layer  { 2 }

sub nbtwalk { (shift)->_walk_body('nbtstat', @_) }

sub nbtstat  {
  my ($self, $job) = @_;

  my $device = get_device($job->device)
    or job_error("nbtstat failed: unable to interpret device parameter");
  my $host = $device->ip;

  # failsafe, should not be needed with skip checks
  unless (is_macsuckable($device)) {
      return job_defer("nbtstat deferred: $host is not macsuckable");
  }

  # get list of nodes on device
  my $interval = (setting('nbtstat_max_age') || 7) . ' day';
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

  # Unless we have IP's don't bother
  if (scalar @nodes) {
    # filter exclusions from config
    @nodes = grep { is_nbtstatable( $_ ) } @nodes;

    # setup the hash nbtstat_resolve_async expects
    my @ips = map {+{'ip' => $_}} @nodes;
    my $now = 'to_timestamp('. (join '.', gettimeofday) .')';

    my $resolved_nodes = nbtstat_resolve_async(\@ips);

    # update node_nbt with status entries
    foreach my $result (@$resolved_nodes) {
      if (defined $result->{'nbname'}) {
        store_nbt($result, $now);
      }
    }
  }

  return job_done("Ended nbtstat for $host");
}

1;
