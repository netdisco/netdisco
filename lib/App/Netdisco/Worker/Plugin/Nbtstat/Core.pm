package App::Netdisco::Worker::Plugin::Nbtstat::Core;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Nbtstat qw/nbtstat_resolve_async store_nbt/;
use App::Netdisco::Util::Node 'is_nbtstatable';
use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $host = $job->device->ip;

  # get list of nodes on device
  my $interval = (setting('nbtstat_max_age') || 7) . ' day';
  my $rs = schema('netdisco')->resultset('NodeIp')->search({
    -bool => 'me.active',
    -bool => 'nodes.active',
    'nodes.switch' => $host,
    'me.time_last' => \[ '>= now() - ?::interval', $interval ],
  },{
    join => 'nodes',
    columns => 'ip',
    distinct => 1,
  })->ip_version(4);

  my @ips = map {+{'ip' => $_}}
            grep { is_nbtstatable( $_ ) }
            $rs->get_column('ip')->all;

  # Unless we have IPs don't bother
  if (scalar @ips) {
    my $now = 'to_timestamp('. (join '.', gettimeofday) .')';
    my $resolved_nodes = nbtstat_resolve_async(\@ips);

    # update node_nbt with status entries
    foreach my $result (@$resolved_nodes) {
      if (defined $result->{'nbname'}) {
        store_nbt($result, $now);
      }
    }
  }

  return Status->done("Ended nbtstat for $host");
});

true;
