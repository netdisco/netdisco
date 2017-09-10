package App::Netdisco::Worker::Plugin::Discover::Wireless;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use Dancer::Plugin::DBIC 'schema';

register_worker({ stage => 'second', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $ssidlist = $snmp->i_ssidlist;
  return Status->done("Ended discover for $device")
    unless scalar keys %$ssidlist;

  my $interfaces = $snmp->interfaces;
  my $ssidbcast  = $snmp->i_ssidbcast;
  my $ssidmac    = $snmp->i_ssidmac;
  my $channel    = $snmp->i_80211channel;
  my $power      = $snmp->dot11_cur_tx_pwr_mw;

  # build device ssid list suitable for DBIC
  my @ssids;
  foreach my $entry (keys %$ssidlist) {
      (my $iid = $entry) =~ s/\.\d+$//;
      my $port = $interfaces->{$iid};

      if (not $port) {
          debug sprintf ' [%s] wireless - ignoring %s (no port mapping)',
            $device->ip, $iid;
          next;
      }

      push @ssids, {
          port      => $port,
          ssid      => $ssidlist->{$entry},
          broadcast => $ssidbcast->{$entry},
          bssid     => $ssidmac->{$entry},
      };
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->ssids->delete;
    debug sprintf ' [%s] wireless - removed %d SSIDs',
      $device->ip, $gone;
    $device->ssids->populate(\@ssids);
    debug sprintf ' [%s] wireless - added %d new SSIDs',
      $device->ip, scalar @ssids;
  });

  # build device channel list suitable for DBIC
  my @channels;
  foreach my $entry (keys %$channel) {
      my $port = $interfaces->{$entry};

      if (not $port) {
          debug sprintf ' [%s] wireless - ignoring %s (no port mapping)',
            $device->ip, $entry;
          next;
      }

      push @channels, {
          port    => $port,
          channel => $channel->{$entry},
          power   => $power->{$entry},
      };
  }

  schema('netdisco')->txn_do(sub {
    my $gone = $device->wireless_ports->delete;
    debug sprintf ' [%s] wireless - removed %d wireless channels',
      $device->ip, $gone;
    $device->wireless_ports->populate(\@channels);
    debug sprintf ' [%s] wireless - added %d new wireless channels',
      $device->ip, scalar @channels;
  });

  return Status->done('Ended discover for '. $device->ip);
});

true;
