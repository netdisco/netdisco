package App::Netdisco::Daemon::Worker::Poller::Arpnip;

use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Core::Arpnip 'do_arpnip';
use App::Netdisco::Util::Device qw/get_device is_arpnipable can_nodenames/;

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
      action => 'nodenames',
      status => 'queued',
      username => $job->username,
      userip => $job->userip,
    });
  });
};

# run a nodenames job for one device
sub nodenames {
  my ($self, $job) = @_;

  my $host = NetAddr::IP::Lite->new($job->device);
  my $device = get_device($host->addr);
  my $jobqueue = schema('netdisco')->resultset('Admin');

  if ($device->ip eq '0.0.0.0') {
      return job_error("nodenames failed: no device param (need -d ?)");
  }

  unless (can_nodenames($device->ip)) {
      return job_defer("nodenames deferred: cannot run for $host");
  }

  resolve_node_names($device);

  return job_done("Ended nodenames for ". $host->addr);
}

1;
