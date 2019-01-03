package App::Netdisco::Worker::Plugin::Macsuck::WirelessNodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("macsuck failed: could not SNMP connect to $device");

  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';

  my $cd11_txrate = $snmp->cd11_txrate;
  return unless $cd11_txrate and scalar keys %$cd11_txrate;

  return Status->info(sprintf ' [%s] macsuck - dot11 info available but skipped due to config',
    $device->ip) unless setting('store_wireless_clients');

  my $cd11_rateset = $snmp->cd11_rateset();
  my $cd11_uptime  = $snmp->cd11_uptime();
  my $cd11_sigstrength = $snmp->cd11_sigstrength();
  my $cd11_sigqual = $snmp->cd11_sigqual();
  my $cd11_mac     = $snmp->cd11_mac();
  my $cd11_port    = $snmp->cd11_port();
  my $cd11_rxpkt   = $snmp->cd11_rxpkt();
  my $cd11_txpkt   = $snmp->cd11_txpkt();
  my $cd11_rxbyte  = $snmp->cd11_rxbyte();
  my $cd11_txbyte  = $snmp->cd11_txbyte();
  my $cd11_ssid    = $snmp->cd11_ssid();

  while (my ($idx, $txrates) = each %$cd11_txrate) {
    my $rates = $cd11_rateset->{$idx};
    my $mac   = $cd11_mac->{$idx};
    next unless defined $mac; # avoid null entries
          # there can be more rows in txrate than other tables

    my $txrate  = (ref $txrates and defined $txrates->[$#$txrates])
      ? int($txrates->[$#$txrates])
      : undef;

    my $maxrate = (ref $rates and defined $rates->[$#$rates])
      ? int($rates->[$#$rates])
      : undef;

    my $ssid = $cd11_ssid->{$idx} || 'unknown';

    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('NodeWireless')
        ->search({ 'me.mac' => $mac, 'me.ssid' => $ssid })
        ->update_or_create({
          txrate  => $txrate,
          maxrate => $maxrate,
          uptime  => $cd11_uptime->{$idx},
          rxpkt   => $cd11_rxpkt->{$idx},
          txpkt   => $cd11_txpkt->{$idx},
          rxbyte  => $cd11_rxbyte->{$idx},
          txbyte  => $cd11_txbyte->{$idx},
          sigqual => $cd11_sigqual->{$idx},
          sigstrength => $cd11_sigstrength->{$idx},
          time_last => \$now,
        }, {
          order_by => [qw/mac ssid/],
          for => 'update',
        });
    });
  }

  return Status->info(sprintf ' [%s] macsuck - processed %s wireless nodes',
    $device->ip, scalar keys %{ $cd11_txrate });
});

true;
