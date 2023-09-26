package App::Netdisco::Worker::Plugin::Internal::BackendFQDN;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Net::Domain 'hostfqdn';
use Scalar::Util 'blessed';

register_worker({ phase => 'check', driver => 'direct' }, sub {
  my ($job, $workerconf) = @_;
  my $action = $job->action or return;

  # if the job is running at CLI it may need a BACKEND setting
  return unless scalar grep {$_ eq $action} @{ setting('deferrable_actions') }
    and not setting('workers')->{'BACKEND'};

  # this can take a few seconds - only do it once
  info 'resolving backend hostname...';
  setting('workers')->{'BACKEND'} ||= (hostfqdn || 'fqdn-undefined');

  debug sprintf 'Backend identity set to %s', setting('workers')->{'BACKEND'};
});

true;
