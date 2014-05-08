package App::Netdisco::Daemon::Worker::Poller::Common;

use Dancer qw/:moose :syntax :script/;

use App::Netdisco::Util::SNMP 'snmp_connect';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Daemon::Util ':all';
use Dancer::Plugin::DBIC 'schema';

use NetAddr::IP::Lite ':lower';

use Role::Tiny;
use namespace::clean;

# queue a job for all devices known to Netdisco
sub _walk_body {
  my ($self, $job_type, $job) = @_;

  my $layer_method = $job_type .'_layer';
  my $job_layer = $self->$layer_method;

  my %queued = map {$_ => 1} $self->jq_queued($job_type);
  my @devices = schema('netdisco')->resultset('Device')
    ->has_layer($job_layer)->get_column('ip')->all;
  my @filtered_devices = grep {!exists $queued{$_}} @devices;

  $self->jq_insert([
      map {{
          device => $_,
          action => $job_type,
          username => $job->username,
          userip => $job->userip,
      }} (@filtered_devices)
  ]);

  return job_done("Queued $job_type job for all devices");
}

sub _single_body {
  my ($self, $job_type, $job) = @_;

  my $action_method = $job_type .'_action';
  my $job_action = $self->$action_method;

  my $layer_method = $job_type .'_layer';
  my $job_layer = $self->$layer_method;

  my $host = NetAddr::IP::Lite->new($job->device);
  my $device = get_device($host->addr);

  if ($device->in_storage
      and $device->vendor and $device->vendor eq 'netdisco') {
      return job_done("$job_type skipped: $host is pseudo-device");
  }

  my $filter_method = $job_type .'_filter';
  my $job_filter = $self->$filter_method;

  unless ($job_filter->($device->ip)) {
      return job_defer("$job_type deferred: $host is not ${job_type}able");
  }

  my $snmp = snmp_connect($device);
  if (!defined $snmp) {
      return job_error("$job_type failed: could not SNMP connect to $host");
  }

  unless ($snmp->has_layer( $job_layer )) {
      return job_done("Skipped $job_type for device $host without OSI layer $job_layer capability");
  }

  $job_action->($device, $snmp);

  return job_done("Ended $job_type for ". $host->addr);
}

sub _single_node_body {
  my ($self, $job_type, $node, $now) = @_;

  my $action_method = $job_type .'_action';
  my $job_action = $self->$action_method;

  my $filter_method = $job_type .'_filter';
  my $job_filter = $self->$filter_method;

  unless ($job_filter->($node)) {
      return job_defer("$job_type deferred: $node is not ${job_type}able");
  }

  $job_action->($node, $now);

  # would be ignored if wrapped in a loop
  return job_done("Ended $job_type for $node");
}

1;
