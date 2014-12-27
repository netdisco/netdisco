package App::Netdisco::Core::Macsuck;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::PortMAC 'get_port_macs';
use App::Netdisco::Util::Node 'check_mac';
use App::Netdisco::Util::SNMP qw/snmp_comm_reindex get_comm_reindex_vlan_list/;
use Time::HiRes 'gettimeofday';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  do_macsuck
  store_node
  store_wireless_client_info
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Core::Macsuck

=head1 DESCRIPTION

Helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 do_macsuck( $device, $snmp )

Given a Device database object, and a working SNMP connection, connect to a
device and discover the MAC addresses listed against each physical port
without a neighbor.

If the device has VLANs, C<do_macsuck> will walk each VLAN to get the MAC
addresses from there.

It will also gather wireless client information if C<store_wireless_clients>
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
  
  my $ip = $device->ip;

  # would be possible just to use now() on updated records, but by using this
  # same value for them all, we can if we want add a job at the end to
  # select and do something with the updated set (see set archive, below)
  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';
  my $total_nodes = 0;

  # do this before we start messing with the snmp community string
  store_wireless_client_info($device, $snmp, $now);

  # cache the device ports to save hitting the database for many single rows
  my $device_ports = {map {($_->port => $_)}
                          $device->ports(undef, {prefetch => 'neighbor_alias'})->all};
  my $port_macs = get_port_macs();
  my $interfaces = $snmp->interfaces;

  # get forwarding table data via basic snmp connection
  my $fwtable = _walk_fwtable($device, $snmp, $interfaces, $port_macs, $device_ports);

  # ...then per-vlan if supported
  my @vlan_list = get_comm_reindex_vlan_list($device, $snmp);
  foreach my $vlan (@vlan_list) {
      snmp_comm_reindex($snmp, $device, $vlan);
      my $pv_fwtable = _walk_fwtable($device, $snmp, $interfaces, $port_macs, $device_ports, $vlan);
      $fwtable = {%$fwtable, %$pv_fwtable};
  }

  # now it's time to call store_node for every node discovered
  # on every port on every vlan on this device.

  # reverse sort allows vlan 0 entries to be included only as fallback
  foreach my $vlan (reverse sort keys %$fwtable) {
      foreach my $port (keys %{ $fwtable->{$vlan} }) {
          debug sprintf ' [%s] macsuck - port %s vlan %s : %s nodes',
            $ip, $port, $vlan, scalar keys %{ $fwtable->{$vlan}->{$port} };

          # make sure this port is UP in netdisco (unless it's a lag master,
          # because we can still see nodes without a functioning aggregate)
          $device_ports->{$port}->update({up_admin => 'up', up => 'up'})
            if not $device_ports->{$port}->is_master;

          foreach my $mac (keys %{ $fwtable->{$vlan}->{$port} }) {

              # remove vlan 0 entry for this MAC addr
              delete $fwtable->{0}->{$_}->{$mac}
                for keys %{ $fwtable->{0} };

              ++$total_nodes;
              store_node($ip, $vlan, $port, $mac, $now);
          }
      }
  }

  debug sprintf ' [%s] macsuck - %s updated forwarding table entries',
    $ip, $total_nodes;

  # a use for $now ... need to archive dissapeared nodes
  my $archived = 0;

  if (setting('node_freshness')) {
      $archived = schema('netdisco')->resultset('Node')->search({
        switch => $ip,
        time_last => \[ "< ($now - ?::interval)",
          setting('node_freshness') .' minutes' ],
      })->update({ active => \'false' });
  }

  debug sprintf ' [%s] macsuck - removed %d fwd table entries to archive',
    $ip, $archived;

  $device->update({last_macsuck => \$now});
}

=head2 store_node( $ip, $vlan, $port, $mac, $now? )

Writes a fresh entry to the Netdisco C<node> database table. Will mark old
entries for this data as no longer C<active>.

All four fields in the tuple are required. If you don't know the VLAN ID,
Netdisco supports using ID "0".

Optionally, a fifth argument can be the literal string passed to the time_last
field of the database record. If not provided, it defauls to C<now()>.

=cut

sub store_node {
  my ($ip, $vlan, $port, $mac, $now) = @_;
  $now ||= 'now()';
  $vlan ||= 0;

  schema('netdisco')->txn_do(sub {
    my $nodes = schema('netdisco')->resultset('Node');

    my $old = $nodes->search(
        { mac   => $mac,
          vlan   => $vlan,
          -bool => 'active',
          -not  => {
                    switch => $ip,
                    port   => $port,
                  },
        })->update( { active => \'false' } );

    # new data
    $nodes->update_or_create(
      {
        switch => $ip,
        port => $port,
        vlan => $vlan,
        mac => $mac,
        active => \'true',
        oui => substr($mac,0,8),
        time_last => \$now,
        (($old != 0) ? (time_recent => \$now) : ()),
      },
      {
        key => 'primary',
        for => 'update',
      }
    );
  });
}

# walks the forwarding table (BRIDGE-MIB) for the device and returns a
# table of node entries.
sub _walk_fwtable {
  my ($device, $snmp, $interfaces, $port_macs, $device_ports, $comm_vlan) = @_;
  my $skiplist = {}; # ports through which we can see another device
  my $cache = {};

  my $fw_mac   = $snmp->fw_mac;
  my $fw_port  = $snmp->fw_port;
  my $fw_vlan  = $snmp->qb_fw_vlan;
  my $bp_index = $snmp->bp_index;

  # to map forwarding table port to device port we have
  #   fw_port -> bp_index -> interfaces

  while (my ($idx, $mac) = each %$fw_mac) {
      my $bp_id = $fw_port->{$idx};
      next unless check_mac($device, $mac);

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

      if (exists $skiplist->{$port}) {
          debug sprintf
            ' [%s] macsuck %s - seen another device thru port %s - skipping.',
            $device->ip, $mac, $port;
          next;
      }

      # this uses the cached $ports resultset to limit hits on the db
      my $device_port = $device_ports->{$port};

      unless (defined $device_port) {
          debug sprintf
            ' [%s] macsuck %s - port %s is not in database - skipping.',
            $device->ip, $mac, $port;
          next;
      }

      my $vlan = $fw_vlan->{$idx} || $comm_vlan || '0';

      # check to see if the port is connected to another device
      # and if we have that device in the database.

      # we have several ways to detect "uplink" port status:
      #  * a neighbor was discovered using CDP/LLDP
      #  * a mac addr is seen which belongs to any device port/interface
      #  * (TODO) admin sets is_uplink_admin on the device_port

      if ($device_port->is_uplink) {
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
          elsif (not setting('macsuck_bleed')) {
              debug sprintf
                ' [%s] macsuck %s - port %s is detected uplink - skipping.',
                $device->ip, $mac, $port;

              $skiplist->{$port} = [ $vlan, $mac ] # remember for later
                if exists $port_macs->{$mac};
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
          $device_port->update({is_uplink => \'true'});

          # when there's no CDP/LLDP, we only want to gather macs at the
          # topology edge, hence skip ports with known device macs.
          if (not setting('macsuck_bleed')) {
                debug sprintf ' [%s] macsuck %s - adding port %s to skiplist',
                    $device->ip, $mac, $port;

                $skiplist->{$port} = [ $vlan, $mac ]; # remember for later
                next;
          }
      }

      # possibly move node to lag master
      if (defined $device_port->slave_of
            and exists $device_ports->{$device_port->slave_of}) {
          $port = $device_port->slave_of;
          $device_ports->{$port}->update({is_uplink => \'true'});
      }

      ++$cache->{$vlan}->{$port}->{$mac};
  }

  # restore MACs of neighbor devices.
  # this is when we have a "possible uplink" detected but we still want to
  # record the single MAC of the neighbor device so it works in Node search.
  foreach my $port (keys %$skiplist) {
      my ($vlan, $mac) = @{ $skiplist->{$port} };
      delete $cache->{$_}->{$port} for keys %$cache; # nuke nodes on all VLANs
      ++$cache->{$vlan}->{$port}->{$mac};
  }

  return $cache;
}

=head2 store_wireless_client_info( $device, $snmp, $now? )

Given a Device database object, and a working SNMP connection, connect to a
device and discover 802.11 related information for all connected wireless
clients.

If the device doesn't support the 802.11 MIBs, then this will silently return.

If the device does support the 802.11 MIBs but Netdisco's configuration
does not permit polling (C<store_wireless_clients> must be true) then a debug
message is logged and the subroutine returns.

Otherwise, client information is gathered and stored to the database.

Optionally, a third argument can be the literal string passed to the time_last
field of the database record. If not provided, it defauls to C<now()>.

=cut

sub store_wireless_client_info {
  my ($device, $snmp, $now) = @_;
  $now ||= 'now()';

  my $cd11_txrate = $snmp->cd11_txrate;
  return unless $cd11_txrate and scalar keys %$cd11_txrate;

  if (setting('store_wireless_clients')) {
      debug sprintf ' [%s] macsuck - gathering wireless client info',
        $device->ip;
  }
  else {
      debug sprintf ' [%s] macsuck - dot11 info available but skipped due to config',
        $device->ip;
      return;
  }

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
}

1;
