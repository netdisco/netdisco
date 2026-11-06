package App::NetdiscoX::Worker::Plugin::TestManagedConfig;

# Reports the roles and named groups as CONFIG holds them while a job runs,
# so a test can see what a real Runner pass gives the job's checks.

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';
use JSON::PP ();

register_worker({ phase => 'main' }, sub {
  return Status->done(JSON::PP->new->canonical->encode({
    roles  => setting('portctl_by_role'),
    groups => setting('host_groups'),
  }));
});

true;
