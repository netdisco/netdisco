package App::NetdiscoX::Worker::Plugin::TestRoles;

# A job whose only work is one device role check, so xt/146 can run jobs one
# after another in one process, as netdisco-do does, and see which roles each
# used. The job's username slot carries a fake user object, so no users table
# is needed.

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Port 'device_acl_by_role_check';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  return (device_acl_by_role_check($job->device, $job->username)
    ? Status->done('the role allows the device')
    : Status->error('the role refuses the device'));
});

true;
