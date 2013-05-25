package App::Netdisco::Core::Macsuck;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::DB::ExplicitLocking ':modes';
use App::Netdisco::Util::PortMAC ':all';
use Time::HiRes 'gettimeofday';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ do_macsuck /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Core::Macsuck

=head1 DESCRIPTION

Helper subroutine to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 do_macsuck( $device, $snmp )

Given a Device database object, and a working SNMP connection, connect to a
device and discover the MAC addresses listed against each physical port
without a neighbor.

If the device has VLANs, C<do_macsuck> will walk each VALN to get the MAC
addresses from there.

It will also gather wireless client information if C<store_wireless_client>
configuration setting is enabled.

=cut

sub do_macsuck {
  my ($device, $snmp) = @_;

  unless ($device->in_storage) {
      debug sprintf
        ' [%s] macsuck - skipping device not yet discovered',
        $device->ip;
      return;
  }

  # would be possible just to use now() on updated records, but by using this
  # same value for them all, we _can_ if we want add a job at the end to
  # select and do something with the updated set (no reason to yet, though)
  my $now = join '.', gettimeofday;
  my $total_nodes = 0;

  # do this before we start messing with the snmp community string
  _wireless_client_info($device, $snmp, $now)
    if setting('store_wireless_client');

  my $port_macs = get_port_macs($device);
  my $fwtable = { 0 => _walk_fwtable($device, $snmp, $port_macs) };

  my @vlan_list = _get_vlan_list($device, $snmp);
  foreach my $vlan (@vlan_list) {
      _snmp_comm_reindex($snmp, $vlan);
      $fwtable->{$vlan} = _walk_fwtable($device, $snmp, $port_macs);
  }

  # cache the device ports so we can look at them for each mac found
  my $uplink_cache = {};
  my $ports = $device->ports;
  while (my $p = $ports->next) {
      $uplink_cache->{ $p->port } = $p->get_column('maybe_uplink');
  }

  # now it's time to call _store_node for every node discovered
  # on every port on every vlan on every device.

  foreach my $vlan (sort keys %$fwtable) {
      foreach my $port (keys %{ $fwtable->{$vlan} }) {
          if ($uplink_cache->{$port}) {
              debug sprintf
                ' [%s] macsuck - port %s is uplink, topo broken - skipping.',
                $device->ip, $port;
              next;
          }

          debug sprintf ' [%s] macsuck - port %s vlan %s : %s nodes',
            $device->ip, $port, $vlan, scalar keys %{ $fwtable->{$vlan}->{$port} };

          MAC: foreach my $mac (keys %{ $fwtable->{$vlan}->{$port} }) {
              # skip if vlan is 0 and mac exists in another vlan
              if ($vlan == 0) {
                  foreach my $zv (keys %$fwtable) {
                      next if $zv == 0;
                      foreach my $zp (keys %{ $fwtable->{$zv} }) {
                          next MAC if exists $fwtable->{$zv}->{$zp}->{$mac};
                      }
                  }
              }

              ++$total_nodes;
              _store_node($device->ip, $vlan, $port, $mac, $now);
          }
      }
  }

  debug sprintf ' [%s] macsuck - %s forwarding table entries',
    $device->ip, $total_nodes;
  $device->update({last_macsuck => \"to_timestamp($now)"});
}

sub _wireless_client_info {
  my ($device, $snmp, $now) = @_;

  debug sprintf ' [%s] macsuck - wireless client info', $device->ip;

  my $cd11_txrate = $snmp->cd11_txrate;
  return unless $cd11_txrate and scalar keys %$cd11_txrate;

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
      
      my $txrate  = defined $txrates->[$#$txrates]
        ? int($txrates->[$#$txrates])
        : undef;

      my $maxrate = defined $rates->[$#$rates]
        ? int($rates->[$#$rates])
        : undef;

      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('NodeWireless')
          ->search({ mac => $mac })
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
            ssid    => ($cd11_ssid->{$idx} || 'unknown'),
            time_last => \"to_timestamp($now)",
          }, { for => 'update' });
      });
  }
}

sub _store_node {
  my ($ip, $vlan, $port, $mac, $now) = @_;

  schema('netdisco')->txn_do(sub {
    my $nodes = schema('netdisco')->resultset('Node');

    my $old = $nodes->search(
      {
        mac => $mac,
        vlan => $vlan,
        -bool => 'active',
        -not => {
          switch => $ip,
          port => $port,
        },
      });

    # selecting the data triggers row lock
    # and get the count so we know whether to set time_recent
    my $old_count = scalar $old->search(undef,
      {
        # ORDER BY FOR UPDATE avoids need for table lock
        order_by => [qw/switch vlan port mac/],
        for => 'update',
      })->all;

    $old->update({ active => \'false' });

    my $new = $nodes->search(
      {
        'me.switch' => $ip,
        'me.port' => $port,
        'me.mac' => $mac,
      },
      {
        # ORDER BY FOR UPDATE avoids need for table lock
        order_by => [qw/switch vlan port mac/],
        for => 'update',
      });

    # trigger row lock
    $new->search({vlan => [$vlan, 0, undef]})->all;

    # upgrade old schema
    $new->search({vlan => [$vlan, 0, undef]})
      ->update({vlan => $vlan});

    $new->update_or_create({
      vlan => $vlan,
      active => \'true',
      oui => substr($mac,0,8),
      time_last => \"to_timestamp($now)",
      ($old_count ? (time_recent => \"to_timestamp($now)") : ()),
    });
  });
}

# make a new snmp connection to $device using community indexing
sub _snmp_comm_reindex {
  my ($snmp, $vlan) = @_;

  my $ver  = $snmp->snmp_ver;
  my $comm = $snmp->snmp_comm;

  if ($ver == 3) {
      $snmp->update(Context => "vlan-$vlan");
  }
  else {
      $snmp->update(Community => $comm . '@' . $vlan);
  }
}

# return a list of vlan numbers which are OK to macsuck on this device
sub _get_vlan_list {
  my ($device, $snmp) = @_;

  return () unless $snmp->cisco_comm_indexing;

  my (%vlans, %vlan_names);
  my $i_vlan = $snmp->i_vlan || {};

  # get list of vlans in use
  while (my ($idx, $vlan) = each %$i_vlan) {
      # hack: if vlan id comes as 1.142 instead of 142
      $vlan =~ s/^\d+\.//;

      ++$vlans{$vlan};
  }

  unless (scalar keys %vlans) {
      debug sprintf ' [%s] macsuck - no VLANs found.', $device->ip;
      return ();
  }

  my $v_name = $snmp->v_name || {};
  
  # get vlan names (required for config which filters by name)
  while (my ($idx, $name) = each %$v_name) {
      # hack: if vlan id comes as 1.142 instead of 142
      (my $vlan = $idx) =~ s/^\d+\.//;

      # just in case i_vlan is different to v_name set
      ++$vlans{$vlan};

      $vlan_names{$vlan} = $name;
  }

  debug sprintf ' [%s] macsuck - VLANs: %s', $device->ip,
    (join ',', sort keys %vlans);

  my @ok_vlans = ();
  foreach my $vlan (sort keys %vlans) {
      my $name = $vlan_names{$vlan} || '(unnamed)';

      # FIXME: macsuck_no_vlan
      # FIXME: macsuck_no_devicevlan

      if (setting('macsuck_no_unnamed') and $name eq '(unnamed)') {
          debug sprintf
            ' [%s] macsuck VLAN %s - skipped by macsuck_no_unnamed config',
            $device->ip, $vlan;
          next;
      }

      if ($vlan == 0 or $vlan > 4094) {
          debug sprintf ' [%s] macsuck - invalid VLAN number %s',
            $device->ip, $vlan;
          next;
      }

      # check in use by a port on this device
      if (scalar keys %$i_vlan and not exists $vlans{$vlan}
            and not setting('macsuck_all_vlans')) {

          debug sprintf
            ' [%s] macsuck VLAN %s/%s - not in use by any port - skipping.',
            $device->ip, $vlan, $name;
          next;
      }

      push @ok_vlans, $vlan;
  }

  return @ok_vlans;
}

# walks the forwarding table (BRIDGE-MIB) for the device and returns a
# table of node entries.
sub _walk_fwtable {
  my ($device, $snmp, $port_macs) = @_;
  my $cache = {};

  my $fw_mac   = $snmp->fw_mac;
  my $fw_port  = $snmp->fw_port;
  my $fw_vlan  = $snmp->qb_fw_vlan;
  my $bp_index = $snmp->bp_index;
  my $interfaces = $snmp->interfaces;

  # cache the device ports so we can look at them for each mac found
  my $ports_cache = {};
  my $ports = $device->ports;
  while (my $p = $ports->next) {
      $ports_cache->{ $p->port } = $p;
  }

  # to map forwarding table port to device port we have
  #   fw_port -> bp_index -> interfaces

  while (my ($idx, $mac) = each %$fw_mac) {
      my $bp_id = $fw_port->{$idx};

      unless (defined $bp_id) {
          debug sprintf
            ' [%s] macsuck %s - %s has no fw_port mapping - skipping.',
            $device->ip, $mac, $idx;
          next;
      }

      my $iid = $bp_index->{$bp_id};

      unless (defined $iid) {
          debug sprintf
            ' [%s] macsuck %s - port %s has no bp_index mapping - skipping.',
            $device->ip, $mac, $bp_id;
          next;
      }

      my $port = $interfaces->{$iid};

      unless (defined $port) {
          debug sprintf
            ' [%s] macsuck %s - iid %s has no port mapping - skipping.',
            $device->ip, $mac, $iid;
          next;
      }

      # TODO: add proper port channel support!
      if ($port =~ m/port.channel/i) {
          debug sprintf
            ' [%s] macsuck %s - port %s is LAG member - skipping.',
            $device->ip, $mac, $port;
          next;
      }

      # this uses the cached $ports resultset to limit hits on the db
      my $device_port = $ports_cache->{$port};

      unless (defined $device_port) {
          debug sprintf
            ' [%s] macsuck %s - port %s is not in database - skipping.',
            $device->ip, $mac, $port;
          next;
      }

      # check to see if the port is connected to another device
      # and if we have that device in the database.

      # we have several ways to detect "uplink" port status:
      #  * a neighbor was discovered using CDP/LLDP
      #  * a mac addr is seen which belongs to any device port/interface
      #  * (TODO) admin sets is_uplink on the device_port

      if ($device_port->maybe_uplink) {
          if (my $neighbor = $device_port->neighbor) {
              debug sprintf
                ' [%s] macsuck %s - port %s has neighbor %s - skipping.',
                $device->ip, $mac, $port, $neighbor->ip;
              next;
          }
          elsif (my $remote = $device_port->remote_ip) {
              debug sprintf
                ' [%s] macsuck %s - port %s has undiscovered neighbor %s',
                $device->ip, $mac, $port, $remote;
              # continue!!
          }
          else {
              debug sprintf
                ' [%s] macsuck %s - port %s is detected uplink - skipping.',
                $device->ip, $mac, $port;
              next;
          }
      }

      if (exists $port_macs->{$mac}) {
          my $switch_ip = $port_macs->{$mac};
          if ($device->ip eq $switch_ip) {
              debug sprintf
                ' [%s] macsuck %s - port %s connects to self - skipping.',
                $device->ip, $mac, $port;
              next;
          }

          debug sprintf ' [%s] macsuck %s - port %s is probably an uplink',
            $device->ip, $mac, $port;
          $device_port->update({maybe_uplink => \'true'});

          # when there's no CDP/LLDP, we only want to gather macs at the
          # topology edge, hence skip ports with known device macs.
          next unless setting('macsuck_bleed');
      }

      if ($mac =~ /^([0-9a-f]{2}):/i and ($1 =~ /.(1|3|5|7|9|b|d|f)/i)) {
          debug sprintf ' [%s] macsuck %s is multicast - skipping.',
            $device->ip, $mac;
          next;
      }

      next if $mac eq '00:00:00:00:00:00';
      next if lc($mac) eq 'ff:ff:ff:ff:ff:ff';

      ++$cache->{$port}->{$mac};
  }

  return $cache;
}

1;
