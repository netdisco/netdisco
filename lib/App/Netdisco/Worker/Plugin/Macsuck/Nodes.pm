package App::Netdisco::Worker::Plugin::Macsuck::Nodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'check_acl_no';
use App::Netdisco::Util::PortMAC 'get_port_macs';
use App::Netdisco::Util::Device 'match_to_setting';
use App::Netdisco::Util::Node 'check_mac';
use App::Netdisco::Util::SNMP 'snmp_comm_reindex';
use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';
use Scope::Guard 'guard';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("macsuck failed: could not SNMP connect to $device");

  # would be possible just to use now() on updated records, but by using this
  # same value for them all, we can if we want add a job at the end to
  # select and do something with the updated set (see set archive, below)
  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';
  my $total_nodes = 0;

  # cache the device ports to save hitting the database for many single rows
  my $device_ports = {map {($_->port => $_)}
                          $device->ports(undef, {prefetch => {neighbor_alias => 'device'}})->all};
  my $port_macs = get_port_macs();
  my $interfaces = $snmp->interfaces;

  # get forwarding table data via basic snmp connection
  my $fwtable = walk_fwtable($device, $interfaces, $port_macs, $device_ports);

  # ...then per-vlan if supported
  my @vlan_list = get_vlan_list($device);
  {
    my $guard = guard { snmp_comm_reindex($snmp, $device, 0) };
    foreach my $vlan (@vlan_list) {
      snmp_comm_reindex($snmp, $device, $vlan);
      my $pv_fwtable =
        walk_fwtable($device, $interfaces, $port_macs, $device_ports, $vlan);
      $fwtable = {%$fwtable, %$pv_fwtable};
    }
  }

  # now it's time to call store_node for every node discovered
  # on every port on every vlan on this device.

  # reverse sort allows vlan 0 entries to be included only as fallback
  foreach my $vlan (reverse sort keys %$fwtable) {
      foreach my $port (keys %{ $fwtable->{$vlan} }) {
          my $vlabel = ($vlan ? $vlan : 'unknown');
          debug sprintf ' [%s] macsuck - port %s vlan %s : %s nodes',
            $device->ip, $port, $vlabel, scalar keys %{ $fwtable->{$vlan}->{$port} };

          # make sure this port is UP in netdisco (unless it's a lag master,
          # because we can still see nodes without a functioning aggregate)
          $device_ports->{$port}->update({up_admin => 'up', up => 'up'})
            if not $device_ports->{$port}->is_master;

          foreach my $mac (keys %{ $fwtable->{$vlan}->{$port} }) {

              # remove vlan 0 entry for this MAC addr
              delete $fwtable->{0}->{$_}->{$mac}
                for keys %{ $fwtable->{0} };

              ++$total_nodes;
              store_node($device->ip, $vlan, $port, $mac, $now);
          }
      }
  }

  debug sprintf ' [%s] macsuck - %s updated forwarding table entries',
    $device->ip, $total_nodes;

  # a use for $now ... need to archive dissapeared nodes
  my $archived = 0;

  if (setting('node_freshness')) {
    $archived = schema('netdisco')->resultset('Node')->search({
      switch => $device->ip,
      time_last => \[ "< ($now - ?::interval)",
        setting('node_freshness') .' minutes' ],
    })->update({ active => \'false' });
  }

  debug sprintf ' [%s] macsuck - removed %d fwd table entries to archive',
    $device->ip, $archived;

  $device->update({last_macsuck => \$now});
  return Status->done("Ended macsuck for $device");
});

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
          # where vlan is unknown, need to archive on all other vlans
          ($vlan ? (vlan => $vlan) : ()),
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

# return a list of vlan numbers which are OK to macsuck on this device
sub get_vlan_list {
  my $device = shift;

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return (); # already checked!

  return () unless $snmp->cisco_comm_indexing;

  my (%vlans, %vlan_names);
  my $i_vlan = $snmp->i_vlan || {};
  my $trunks = $snmp->i_vlan_membership || {};
  my $i_type = $snmp->i_type || {};

  # get list of vlans in use
  while (my ($idx, $vlan) = each %$i_vlan) {
      # hack: if vlan id comes as 1.142 instead of 142
      $vlan =~ s/^\d+\.//;
      
      # VLANs are ports interfaces capture VLAN, but don't count as in use
      # Port channels are also 'propVirtual', but capture while checking
      # trunk VLANs below
      if (exists $i_type->{$idx} and $i_type->{$idx} eq 'propVirtual') {
        $vlans{$vlan} ||= 0;
      }
      else {
        ++$vlans{$vlan};
      }
      foreach my $t_vlan (@{$trunks->{$idx}}) {
        ++$vlans{$t_vlan};
      }
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
      # capture the VLAN, but it's not in use on a port
      $vlans{$vlan} ||= 0;

      $vlan_names{$vlan} = $name;
  }

  debug sprintf ' [%s] macsuck - VLANs: %s', $device->ip,
    (join ',', sort grep {$_} keys %vlans);

  my @ok_vlans = ();
  foreach my $vlan (sort keys %vlans) {
      my $name = $vlan_names{$vlan} || '(unnamed)';

      if (ref [] eq ref setting('macsuck_no_vlan')) {
          my $ignore = setting('macsuck_no_vlan');

          if ((scalar grep {$_ eq $vlan} @$ignore) or
              (scalar grep {$_ eq $name} @$ignore)) {

              debug sprintf
                ' [%s] macsuck VLAN %s - skipped by macsuck_no_vlan config',
                $device->ip, $vlan;
              next;
          }
      }

      if (ref [] eq ref setting('macsuck_no_devicevlan')) {
          my $ignore = setting('macsuck_no_devicevlan');
          my $ip = $device->ip;

          if ((scalar grep {$_ eq "$ip:$vlan"} @$ignore) or
              (scalar grep {$_ eq "$ip:$name"} @$ignore)) {

              debug sprintf
                ' [%s] macsuck VLAN %s - skipped by macsuck_no_devicevlan config',
                $device->ip, $vlan;
              next;
          }
      }

      if (setting('macsuck_no_unnamed') and $name eq '(unnamed)') {
          debug sprintf
            ' [%s] macsuck VLAN %s - skipped by macsuck_no_unnamed config',
            $device->ip, $vlan;
          next;
      }

      if ($vlan > 4094) {
          debug sprintf ' [%s] macsuck - invalid VLAN number %s',
            $device->ip, $vlan;
          next;
      }
      next if $vlan == 0; # quietly skip

      # check in use by a port on this device
      if (!$vlans{$vlan} && !setting('macsuck_all_vlans')) {
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
sub walk_fwtable {
  my ($device, $interfaces, $port_macs, $device_ports, $comm_vlan) = @_;
  my $skiplist = {}; # ports through which we can see another device
  my $cache = {};

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return $cache; # already checked!

  my $fw_mac   = $snmp->fw_mac;
  my $fw_port  = $snmp->fw_port;
  my $fw_vlan  = $snmp->qb_fw_vlan;
  my $bp_index = $snmp->bp_index;

  # to map forwarding table port to device port we have
  #   fw_port -> bp_index -> interfaces

  while (my ($idx, $mac) = each %$fw_mac) {
      my $bp_id = $fw_port->{$idx};
      next unless check_mac($mac, $device);

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

      # WRT #475 this is SAFE because we check against known ports below
      # but we do need the SNMP interface IDs to get the job done
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

      # WRT #475 ... see? :-)
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

      # allow to gather MACs on upstream port for some kinds of device that
      # do not expose MAC address tables via SNMP. relies on prefetched
      # neighbors otherwise it would kill the DB with device lookups.
      my $neigh_cannot_macsuck = eval { # can fail
        check_acl_no(($device_port->neighbor || "0 but true"), 'macsuck_unsupported') ||
        match_to_setting($device_port->remote_type, 'macsuck_unsupported_type') };

      if ($device_port->is_uplink) {
          if ($neigh_cannot_macsuck) {
              debug sprintf
                ' [%s] macsuck %s - port %s neighbor %s without macsuck support',
                $device->ip, $mac, $port,
                (eval { $device_port->neighbor->ip }
                 || ($device_port->remote_ip
                     || $device_port->remote_id || '?'));
              # continue!!
          }
          elsif (my $neighbor = $device_port->neighbor) {
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

          # neighbor exists and Netdisco can speak to it, so we don't want
          # its MAC address. however don't add to skiplist as that would
          # clear all other MACs on the port.
          next if $neigh_cannot_macsuck;

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

true;
