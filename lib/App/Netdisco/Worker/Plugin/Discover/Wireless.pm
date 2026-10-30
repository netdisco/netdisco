package App::Netdisco::Worker::Plugin::Discover::Wireless;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::Util::SNMPText 'decode_snmp_text';
use App::Netdisco::Util::SNMP qw/walk_mark incomplete_walks_for incomplete_walk_message
  incomplete_walk_level/;

# ifIndex and ifIndex.n keys, or a controller's AP MAC and slot keys, in
# numeric order, so a duplicate resolves to the same entry on every run
# whatever the hash order
sub _by_oid {
  my @left  = split m/\./, $a;
  my @right = split m/\./, $b;
  while (@left and @right) {
      my $order = (shift @left) <=> (shift @right);
      return $order if $order;
  }
  return @left <=> @right;
}

sub _build_ssids {
  my ($device, $snmp, $device_ports) = @_;
  my $ssidlist   = $snmp->i_ssidlist   || {};
  my $interfaces = $snmp->interfaces   || {};
  my $ssidbcast  = $snmp->i_ssidbcast  || {};
  my $ssidmac    = $snmp->i_ssidmac    || {};

  my (%ssidseen, @ssids);
  foreach my $entry (sort _by_oid keys %$ssidlist) {
      (my $iid = $entry) =~ s/\.\d+$//;
      my $port = $interfaces->{$iid};

      if (not $port) {
          debug sprintf ' [%s] wireless - ignoring %s (no port mapping)',
            $device->ip, $iid;
          next;
      }

      if (!defined $device_ports->{$port}) {
          debug sprintf ' [%s] wireless - local port %s already skipped, ignoring',
            $device->ip, $port;
          next;
      }

      next unless $ssidmac->{$entry};

      if (exists $ssidseen{$port}{ $ssidmac->{$entry} }) {
          debug sprintf ' [%s] wireless - duplicate bssid %s on port %s',
            $device->ip, $ssidmac->{$entry}, $port;
          next;
      }
      ++$ssidseen{$port}{ $ssidmac->{$entry} };

      push @ssids, {
          ip        => $device->ip,
          port      => $port,
          ssid      => decode_snmp_text($ssidlist->{$entry}, $device, "port $port ssid"),
          broadcast => $ssidbcast->{$entry},
          bssid     => $ssidmac->{$entry},
      };
  }
  return \@ssids;
}

sub _build_channels {
  my ($device, $snmp, $device_ports) = @_;
  my $interfaces = $snmp->interfaces         || {};
  my $channel    = $snmp->i_80211channel     || {};
  my $power      = $snmp->dot11_cur_tx_pwr_mw || {};

  my (%seen, @channels);
  foreach my $entry (sort _by_oid keys %$channel) {
      my $port = $interfaces->{$entry};

      if (not $port) {
          debug sprintf ' [%s] wireless - ignoring %s (no port mapping)',
            $device->ip, $entry;
          next;
      }

      if (!defined $device_ports->{$port}) {
          debug sprintf ' [%s] wireless - local port %s already skipped, ignoring',
            $device->ip, $port;
          next;
      }

      next if $seen{$port}++;

      push @channels, {
          ip      => $device->ip,
          port    => $port,
          channel => $channel->{$entry},
          power   => $power->{$entry},
      };
  }
  return \@channels;
}

sub _store_ssids {
  my ($device, $ssids) = @_;
  schema('netdisco')->txn_do(sub {
    my $rs = schema('netdisco')->resultset('DevicePortSsid');
    $rs->upsert($ssids) if scalar @$ssids;
    my $gone = $rs->remove_unseen({ ip => $device->ip },
      [ map {{ port => $_->{port}, bssid => $_->{bssid} }} @$ssids ]);
    debug sprintf ' [%s] wireless - removed %d SSIDs', $device->ip, $gone;
    debug sprintf ' [%s] wireless - wrote %d SSIDs', $device->ip, scalar @$ssids;
  });
}

sub _store_channels {
  my ($device, $channels) = @_;
  schema('netdisco')->txn_do(sub {
    my $rs = schema('netdisco')->resultset('DevicePortWireless');
    $rs->upsert($channels) if scalar @$channels;
    my $gone = $rs->remove_unseen({ ip => $device->ip },
      [ map {{ port => $_->{port} }} @$channels ]);
    debug sprintf ' [%s] wireless - removed %d wireless channels',
      $device->ip, $gone;
  });
}

# a cut-short walk must not look like a device without SSIDs or channels, so the
# stored rows stand; the SSID list gates both tables, so its failure keeps both
sub _skip_for {
  my ($device, $snmp, $mark, $what, @methods) = @_;
  my @incomplete = incomplete_walks_for($device, $snmp, $mark, @methods);
  return () unless scalar @incomplete;
  my $skipped = incomplete_walk_message($device, $what, @incomplete);
  warning $skipped;
  return ($skipped, incomplete_walk_level(@incomplete));
}

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  # cache the device ports to save hitting the database for many single rows
  my $device_ports = vars->{'device_ports'}
    || { map {($_->port => $_)} $device->ports->all };

  # each table is judged only on the walks its own reads recorded
  my $ssid_mark = walk_mark($snmp);
  my $has_ssids = scalar keys %{ $snmp->i_ssidlist || {} };
  my $ssids = _build_ssids($device, $snmp, $device_ports);
  my ($ssid_skip, $ssid_level) = _skip_for($device, $snmp, $ssid_mark,
    'device_port_ssid', qw/interfaces i_ssidlist i_ssidbcast i_ssidmac/);

  my $channel_mark = walk_mark($snmp);
  my $channels = $has_ssids ? _build_channels($device, $snmp, $device_ports) : [];
  my ($chan_skip, $chan_level) = _skip_for($device, $snmp, $channel_mark,
    'device_port_wireless', qw/interfaces i_ssidlist i_80211channel dot11_cur_tx_pwr_mw/);

  _store_ssids($device, $ssids) unless defined $ssid_skip;
  _store_channels($device, $channels) unless defined $chan_skip;

  my @skips = grep { defined } $ssid_skip, $chan_skip;
  my $level = (grep { ($_ // '') eq 'error' } $ssid_level, $chan_level) ? 'error' : 'info';
  my $status = sprintf ' [%s] wireless - %s SSIDs, %s wireless channels',
    $device->ip,
    (defined $ssid_skip ? 'kept existing' : 'added ' . scalar @$ssids . ' new'),
    (defined $chan_skip ? 'kept existing' : 'added ' . scalar @$channels . ' new');
  $status .= '; ' . join '; ', @skips if scalar @skips;
  return Status->$level($status);
});

true;
