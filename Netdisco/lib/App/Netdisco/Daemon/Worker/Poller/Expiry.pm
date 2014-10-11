package App::Netdisco::Daemon::Worker::Poller::Expiry;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Daemon::Util ':all';

use Role::Tiny;
use namespace::clean;

# expire devices and nodes according to config
sub expire {
  my ($self, $job) = @_;

  if (setting('expire_devices') and setting('expire_devices') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Device')->search({
          last_discover => \[q/< (now() - ?::interval)/,
              (setting('expire_devices') * 86400)],
        })->delete();
      });
  }

  if (setting('expire_nodes') and setting('expire_nodes') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Node')->search({
          time_last => \[q/< (now() - ?::interval)/,
              (setting('expire_nodes') * 86400)],
        })->delete();
      });
  }

  if (setting('expire_nodes_archive') and setting('expire_nodes_archive') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Node')->search({
          -not_bool => 'active',
          time_last => \[q/< (now() - ?::interval)/,
              (setting('expire_nodes_archive') * 86400)],
        })->delete();
      });
  }

  if (setting('expire_jobs') and setting('expire_jobs') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Admin')->search({
          entered => \[q/< (now() - ?::interval)/,
              (setting('expire_jobs') * 86400)],
        })->delete();
      });
  }

  return job_done("Checked expiry for all Devices and Nodes");
}

1;
