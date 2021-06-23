package App::Netdisco::Worker::Plugin::Discover::CanonicalIP;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'check_acl_only';
use App::Netdisco::Util::DNS 'ipv4_from_hostname';
use App::Netdisco::Util::Device 'is_discoverable';
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $old_ip = $device->ip;
  my $new_ip = $old_ip;
  my $revofname = ipv4_from_hostname($snmp->name);

  if (setting('reverse_sysname') and $revofname) {
    if (App::Netdisco::Transport::SNMP->test_connection( $new_ip )) {
      $new_ip = $revofname;
    }
    else {
      debug sprintf ' [%s] device - cannot renumber to %s - SNMP connect failed',
        $old_ip, $revofname;
    }
  }

  if (scalar @{ setting('device_identity') }) {
    my @idmaps = @{ setting('device_identity') };
    my $devips = $device->device_ips->order_by('alias');

    ALIAS: while (my $alias = $devips->next) {
      next if $alias->alias eq $old_ip;

      foreach my $map (@idmaps) {
        next unless ref {} eq ref $map;

        foreach my $key (sort keys %$map) {
          # lhs matches device, rhs matches device_ip
          if (check_acl_only($device, $key)
                and check_acl_only($alias, $map->{$key})) {

            if (not is_discoverable( $alias->alias )) {
              debug sprintf ' [%s] device - cannot renumber to %s - not discoverable',
                $old_ip, $alias->alias;
              next;
            }

            if (App::Netdisco::Transport::SNMP->test_connection( $alias->alias )) {
              $new_ip = $alias->alias;
              last ALIAS;
            }
            else {
              debug sprintf ' [%s] device - cannot renumber to %s - SNMP connect failed',
                $old_ip, $alias->alias;
            }
          }
        }
      }
    } # ALIAS
  }

  return if $new_ip eq $old_ip;

  schema('netdisco')->txn_do(sub {
    my $existing = schema('netdisco')->resultset('Device')->search({
      ip => $new_ip, vendor => $device->vendor, serial => $device->serial,
    });

    if (($job->subaction eq 'with-nodes') and $existing->count) {
      $device->delete;
      return $job->cancel(
        " [$old_ip] device - cancelling fresh discover: already known as $new_ip");
    }

    # discover existing device but change IP, need to remove existing device
    $existing->delete;

    # if target device exists then this will die
    $device->renumber($new_ip)
      or die "cannot renumber to: $new_ip"; # rollback

    # is not done in renumber, but required, otherwise confusing at job end!
    schema('netdisco')->resultset('Admin')
      ->find({job => $job->id})->update({device => $new_ip}) if $job->id;

    return Status->info(sprintf ' [%s] device - changed IP to %s (%s)',
      $old_ip, $device->ip, ($device->dns || ''));
  });
});

true;
