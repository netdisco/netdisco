package App::Netdisco::Worker::Plugin::Expire;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::JobQueue 'jq_insert';
use App::Netdisco::Util::Statistics 'update_stats';
use App::Netdisco::Util::DNS 'ipv4_from_hostname';
use App::Netdisco::DB::ExplicitLocking ':modes';
use App::Netdisco::Util::Permission 'acl_matches_only';

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  if (setting('expire_devices') and ref {} eq ref setting('expire_devices')) {
      foreach my $acl (keys %{ setting('expire_devices') }) {
          my $days = setting('expire_devices')->{$acl};

          schema('netdisco')->txn_do(sub {
            my @hostlist = schema('netdisco')->resultset('Device')->search({
              -not_bool => 'is_pseudo',
              last_discover => \[q/< (LOCALTIMESTAMP - ?::interval)/,
                  ($days * 86400)],
            })->get_column('ip')->all;

            foreach my $ip (@hostlist) {
                next unless acl_matches_only($ip, $acl);

                jq_insert([{
                  device => $ip,
                  action => 'delete',
                }]);

                schema('netdisco')->resultset('UserLog')->create({
                  username => ($ENV{USER} || 'scheduled'),
                  userip => ipv4_from_hostname($job->backend || setting('workers')->{'BACKEND'}),
                  event => 'expire_devices',
                  details => $ip,
                });
            }
          });
      }
  }

  if (setting('expire_nodes') and setting('expire_nodes') > 0) {
      schema('netdisco')->txn_do(sub {
        my $freshness = ((defined setting('expire_nodeip_freshness'))
          ? setting('expire_nodeip_freshness') : setting('expire_nodes'));
        if ($freshness) {
          schema('netdisco')->resultset('NodeIp')->search({
            time_last => \[q/< (LOCALTIMESTAMP - ?::interval)/, ($freshness * 86400)],
          })->delete();
        }

        schema('netdisco')->resultset('Node')->search({
          time_last => \[q/< (LOCALTIMESTAMP - ?::interval)/,
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
            time_last => \[q/< (LOCALTIMESTAMP - ?::interval)/, ($freshness * 86400)],
          })->delete();
        }

        schema('netdisco')->resultset('Node')->search({
          -not_bool => 'active',
          time_last => \[q/< (LOCALTIMESTAMP - ?::interval)/,
              (setting('expire_nodes_archive') * 86400)],
        })->delete();
      });
  }

  # node_wireless is otherwise only cleared when a node row for the same mac
  # is deleted, and a client still seen anywhere keeps its node row fresh, so
  # every (mac, ssid) pair it ever held - an SSID it roamed away from, or an
  # "unknown" row from before a gap in the SSID walk was skipped - would stay
  # for good. Macsuck refreshes time_last on each pair it sees, so age alone
  # tells a pair that is no longer reported. This deliberately does not pick
  # "unknown" out by name: on classes with no cd11_ssid at all it is still the
  # only row a client has, and is refreshed like any other.
  #
  # Unset, it follows node expiry, falling back to the archive age so that a
  # site which keeps active nodes for good but expires archived ones still
  # ages node_wireless out. A NULL time_last is a pair not seen since the
  # column gained its default, as every macsuck sets it, so it goes too.
  my $wireless_age = ((defined setting('expire_node_wireless'))
    ? setting('expire_node_wireless')
    : (setting('expire_nodes') || setting('expire_nodes_archive')));
  if ($wireless_age and $wireless_age > 0) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('NodeWireless')->search({
          -or => [
            { time_last => undef },
            { time_last => \[q/< (LOCALTIMESTAMP - ?::interval)/,
                ($wireless_age * 86400)] },
          ],
        })->delete();
      });
  }

  # also clean up node_ip entries that have no corresponding node
  if (setting('expire_nodeip_orphans')) {
      schema('netdisco')->resultset('NodeIp')->search({
        mac => { -in => schema('netdisco')->resultset('NodeIp')->search(
          { port => undef },
          { join => 'nodes', select => [{ distinct => 'me.mac' }], }
        )->as_query },
      })->delete;
  }

  if (setting('expire_jobs') and setting('expire_jobs') > 0) {
      schema('netdisco')->txn_do_locked('admin', EXCLUSIVE, sub {
        schema('netdisco')->resultset('Admin')->search({
          entered => \[q/< (LOCALTIMESTAMP - ?::interval)/,
              (setting('expire_jobs') * 86400)],
        })->delete();
      });
  }

  if (setting('expire_userlog') and setting('expire_userlog') > 0) {
      schema('netdisco')->txn_do_locked('admin', EXCLUSIVE, sub {
        schema('netdisco')->resultset('UserLog')->search({
          creation => \[q/< (LOCALTIMESTAMP - ?::interval)/,
              (setting('expire_userlog') * 86400)],
        })->delete();
      });
  }

  # now update stats
  update_stats();

  return Status->done('Checked expiry and updated stats');
});

true;
