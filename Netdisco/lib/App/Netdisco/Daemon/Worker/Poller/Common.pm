package App::Netdisco::Daemon::Worker::Poller::Common;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::SNMP 'snmp_connect';
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Daemon::Util ':all';

use NetAddr::IP::Lite ':lower';

use Role::Tiny;
use namespace::clean;

# queue a job for all devices known to Netdisco
sub _walk_body {
  my ($self, $job_type, $job) = @_;

  my $jobqueue = schema('netdisco')->resultset('Admin');
  my $devices = schema('netdisco')->resultset('Device')
    ->search({ip => { -not_in =>
        $jobqueue->search({
          device => { '!=' => undef},
          action => $job_type,
          status => { -like => 'queued%' },
        })->get_column('device')->as_query
    }})->get_column('ip');

  schema('netdisco')->resultset('Admin')->txn_do_locked(sub {
    $jobqueue->populate([
      map {{
          device => $_,
          action => $job_type,
          status => 'queued',
      }} ($devices->all)
    ]);
  });

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

1;
