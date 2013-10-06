package App::Netdisco::Daemon::Worker::Poller::Arpnip;

use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Core::Arpnip 'do_arpnip';
use App::Netdisco::Util::Device qw/get_device is_arpnipable is_nodeip2nameable/;

use App::Netdisco::Core::Arpnip 'resolve_node_names';
use App::Netdisco::Daemon::Util ':all';

use NetAddr::IP::Lite ':lower';

use Role::Tiny;
use Class::Method::Modifiers;
use namespace::clean;

with 'App::Netdisco::Daemon::Worker::Poller::Common';

sub arpnip_action { \&do_arpnip }
sub arpnip_filter { \&is_arpnipable }
sub arpnip_layer { 3 }

sub arpwalk { (shift)->_walk_body('arpnip', @_) }
sub arpnip  { (shift)->_single_body('arpnip', @_) }

after 'arpnip' => sub {
  my ($self, $job) = @_;

  my $host = NetAddr::IP::Lite->new($job->device);
  my $device = get_device($host->addr);
  my $jobqueue = schema('netdisco')->resultset('Admin');

  schema('netdisco')->txn_do(sub {
    $jobqueue->create({
      device => $device->ip,
      action => 'nodeip2name',
      status => 'queued',
      username => $job->username,
      userip => $job->userip,
    });
  });
};

# run a nodeip2name job for one device
sub nodeip2name {
  my ($self, $job) = @_;

  my $host = NetAddr::IP::Lite->new($job->device);
  my $device = get_device($host->addr);
  my $jobqueue = schema('netdisco')->resultset('Admin');

  if ($device->ip eq '0.0.0.0') {
      return job_error("nodeip2name failed: no device param (need -d ?)");
  }

  unless (is_nodeip2nameable($device->ip)) {
      return job_defer("nodeip2name deferred: $host is not nodeip2nameable");
  }

  resolve_node_names($device);

  return job_done("Ended nodeip2name for ". $host->addr);
}

1;
