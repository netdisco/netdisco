package App::Netdisco::Worker::Plugin::Expire;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::Statistics 'update_stats';
use App::Netdisco::DB::ExplicitLocking ':modes';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  if (setting('expire_devices') and setting('expire_devices') > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Device')->search({
          -or => [ 'vendor' => undef, 'vendor' => { '!=' => 'netdisco' }],
          last_discover => \[q/< (now() - ?::interval)/,
              (setting('expire_devices') * 86400)],
        })->delete();
      });
  }

  if (setting('expire_nodes') and setting('expire_nodes') > 0) {
      schema('netdisco')->txn_do(sub {
        my $freshness = ((defined setting('expire_nodeip_freshness'))
          ? setting('expire_nodeip_freshness') : setting('expire_nodes'));
        if ($freshness) {
          schema('netdisco')->resultset('NodeIp')->search({
            time_last => \[q/< (now() - ?::interval)/, ($freshness * 86400)],
          })->delete();
        }

        schema('netdisco')->resultset('Node')->search({
          time_last => \[q/< (now() - ?::interval)/,
              (setting('expire_nodes') * 86400)],
        })->delete();
      });
  }

  if (setting('expire_nodes_archive') and setting('expire_nodes_archive') > 0) {
      schema('netdisco')->txn_do(sub {
        my $freshness = ((defined setting('expire_nodeip_freshness'))
          ? setting('expire_nodeip_freshness') : setting('expire_nodes_archive'));
        if ($freshness) {
          schema('netdisco')->resultset('NodeIp')->search({
            time_last => \[q/< (now() - ?::interval)/, ($freshness * 86400)],
          })->delete();
        }

        schema('netdisco')->resultset('Node')->search({
          -not_bool => 'active',
          time_last => \[q/< (now() - ?::interval)/,
              (setting('expire_nodes_archive') * 86400)],
        })->delete();
      });
  }

  # also have to clean up node_ip that have no correspoding node
  schema('netdisco')->resultset('NodeIp')->search({
    mac => { -in => schema('netdisco')->resultset('NodeIp')->search(
      { port => undef },
      { join => 'nodes', select => [{ distinct => 'me.mac' }], }
    )->as_query },
  })->delete;

  if (setting('expire_jobs') and setting('expire_jobs') > 0) {
      schema('netdisco')->txn_do_locked('admin', 'EXCLUSIVE', sub {
        schema('netdisco')->resultset('Admin')->search({
          entered => \[q/< (now() - ?::interval)/,
              (setting('expire_jobs') * 86400)],
        })->delete();
      });
  }

  if (setting('expire_userlog') and setting('expire_userlog') > 0) {
      schema('netdisco')->txn_do_locked('admin', 'EXCLUSIVE', sub {
        schema('netdisco')->resultset('UserLog')->search({
          creation => \[q/< (now() - ?::interval)/,
              (setting('expire_userlog') * 86400)],
        })->delete();
      });
  }

  # now update stats
  update_stats();

  return Status->done('Checked expiry and updated stats');
});

true;
