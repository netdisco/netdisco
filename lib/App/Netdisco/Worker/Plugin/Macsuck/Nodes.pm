package App::Netdisco::Worker::Plugin::Macsuck::Nodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SSH ();
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::Util::PortMAC 'get_port_macs';
use App::Netdisco::Util::Device 'match_to_setting';
use App::Netdisco::Util::Node 'check_mac';
use App::Netdisco::Util::SNMP 'snmp_comm_reindex';
use App::Netdisco::Util::Web 'sort_port';

use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';
use Scope::Guard 'guard';
use Regexp::Common 'net';
use NetAddr::MAC ();
use List::MoreUtils ();

register_worker({ phase => 'early',
  title => 'prepare common data' }, sub {

  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # would be possible just to use LOCALTIMESTAMP on updated records, but by using this
  # same value for them all, we can if we want add a job at the end to
  # select and do something with the updated set (see set archive, below)
  vars->{'timestamp'} = ($job->is_offline and $job->entered)
    ? (schema('netdisco')->storage->dbh->quote($job->entered) .'::timestamp')
    : 'to_timestamp('. (join '.', gettimeofday) .')::timestamp';

  # initialise the cache
  vars->{'fwtable'} = {};

  # cache the device ports to save hitting the database for many single rows
  vars->{'device_ports'} = {map {($_->port => $_)}
                          $device->ports(undef, {prefetch => ['properties',
                                                              {neighbor_alias => 'device'}]})->all};
});

register_worker({ phase => 'main', driver => 'direct',
  title => 'gather macs from file' }, sub {

  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->info('skip: fwtable data supplied by other source')
    unless $job->is_offline;

  # load cache from file or copy from job param
  my $data = $job->extra;
  my @fwtable = (length $data ? @{ from_json($data) } : ());

  return $job->cancel('data provided but 0 fwd entries found')
    unless scalar @fwtable;

  debug sprintf ' [%s] macsuck - %s forwarding table entries provided',
    $device->ip, scalar @fwtable;

  # rebuild fwtable in format for filtering more easily
  foreach my $node (@fwtable) {
      my $mac = NetAddr::MAC->new(mac => ($node->{'mac'} || ''));
      next unless $node->{'port'} and $mac;
      next if (($mac->as_ieee eq '00:00:00:00:00:00') or ($mac->as_ieee !~ m{^$RE{net}{MAC}$}i));

      vars->{'fwtable'}->{ $node->{'vlan'} || 0 }
                       ->{ $node->{'port'} }
                       ->{ $mac->as_ieee } += 1;
  }

  return Status->done("Received MAC addresses for $device");
});

register_worker({ phase => 'main', driver => 'cli',
  title => 'gather macs from CLI'}, sub {

  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $cli = App::Netdisco::Transport::SSH->session_for($device)
    or return Status->defer("macsuck failed: could not SSH connect to $device");

  # Retrieve data through SSH connection
  my $macs = $cli->macsuck;

  my $nodecount = 0;
  foreach my $vlan (keys %{ $macs }) {
    foreach my $port (keys %{ $macs->{$vlan} }) {
      $nodecount += scalar keys %{ $macs->{$vlan}->{$port} };
    }
  }

  return $job->cancel('data provided but 0 fwd entries found')
    unless $nodecount;

  debug sprintf ' [%s] macsuck - %s forwarding table entries provided',
    $device->ip, $nodecount;

  # get forwarding table and populate fwtable
  vars->{'fwtable'} = $macs;

  return Status->done("Gathered MAC addresses for $device");
});

register_worker({ phase => 'main', driver => 'snmp',
  title => 'gather macs from snmp'}, sub {

  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("macsuck failed: could not SNMP connect to $device");

  # get forwarding table data via basic snmp connection
  my $interfaces = $snmp->interfaces || {};
  vars->{'fwtable'} = walk_fwtable($snmp, $device, $interfaces);

  # ...then per-vlan if supported
  # this will duplicate call sanity_vlans (same as store) but helps efficiency
  my @vlan_list = get_vlan_list($snmp, $device);
  {
    my $guard = guard { snmp_comm_reindex($snmp, $device, 0) };
    foreach my $vlan (@vlan_list) {
      snmp_comm_reindex($snmp, $device, $vlan);
      my $pv_fwtable =
        walk_fwtable($snmp, $device, $interfaces, $vlan);
      vars->{'fwtable'} = {%{ vars->{'fwtable'} }, %$pv_fwtable};
    }
  }

  return Status->done("Gathered MAC addresses for $device");
});


register_worker({ phase => 'store',
  title => 'save macs to database'}, sub {

  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # remove macs on forbidden vlans
  my @vlans = (0, sanity_vlans($device, vars->{'fwtable'}, {}, {}));
  foreach my $vlan (keys %{ vars->{'fwtable'} }) {
      delete vars->{'fwtable'}->{$vlan}
        unless scalar grep {$_ eq $vlan} @vlans;
  }

  # sanity filter the MAC addresses from the device
  vars->{'fwtable'} = sanity_macs( $device, vars->{'fwtable'}, vars->{'device_ports'} );

  # reverse sort allows vlan 0 entries to be included only as fallback
  my $node_count = 0;
  foreach my $vlan (reverse sort keys %{ vars->{'fwtable'} }) {
      foreach my $port (keys %{ vars->{'fwtable'}->{$vlan} }) {
          my $vlabel = ($vlan ? $vlan : 'unknown');
          debug sprintf ' [%s] macsuck - port %s vlan %s : %s nodes',
            $device->ip, $port, $vlabel, scalar keys %{ vars->{'fwtable'}->{$vlan}->{$port} };

          foreach my $mac (keys %{ vars->{'fwtable'}->{$vlan}->{$port} }) {

              # remove vlan 0 entry for this MAC addr
              delete vars->{'fwtable'}->{0}->{$_}->{$mac}
                for keys %{ vars->{'fwtable'}->{0} };

              store_node($device->ip, $vlan, $port, $mac, vars->{'timestamp'});
              ++$node_count;
          }
      }
  }

  debug sprintf ' [%s] macsuck - stored %s forwarding table entries',
    $device->ip, $node_count;

  # a use for $now ... need to archive disappeared nodes
  my $now = vars->{'timestamp'};
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

  my $status = $job->best_status;
  if (Status->$status->level == Status->done->level) {
      $device->update({last_macsuck => \$now});
  }

  return Status->$status("Ended macsuck for $device");
});


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

=head2 store_node( $ip, $vlan, $port, $mac, $now? )

Writes a fresh entry to the Netdisco C<node> database table. Will mark old
entries for this data as no longer C<active>.

All four fields in the tuple are required. If you don't know the VLAN ID,
Netdisco supports using ID "0".

Optionally, a fifth argument can be the literal string passed to the time_last
field of the database record. If not provided, it defaults to C<LOCALTIMESTAMP>.

=cut

sub store_node {
  my ($ip, $vlan, $port, $mac, $now) = @_;
  $now ||= 'LOCALTIMESTAMP';
  $vlan ||= 0;

  # ideally we just store the first 36 bits of the mac in the oui field
  # and then no need for this query. haven't yet worked out the SQL for that.
  my $oui = schema('netdisco')->resultset('Manufacturer')
    ->search({ range => { '@>' =>
      \[q{('x' || lpad( translate( ? ::text, ':', ''), 16, '0')) ::bit(64) ::bigint}, $mac]} },
      { rows => 1, columns => 'base' })->first;

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
    my $row = $nodes->update_or_new(
      {
        switch => $ip,
        port => $port,
        vlan => $vlan,
        mac => $mac,
        active => \'true',
        oui => ($oui ? $oui->base : undef),
        time_last => \$now,
        (($old != 0) ? (time_recent => \$now) : ()),
      },
      {
        key => 'primary',
        for => 'update',
      }
    );

    if (! $row->in_storage) {
        $row->set_column(time_first => \$now);
        $row->insert;
    }
  });
}

# return a list of vlan numbers which are OK to macsuck on this device
sub get_vlan_list {
  my ($snmp, $device) = @_;
  return () unless $snmp->cisco_comm_indexing;

  my (%vlans, %vlan_names, %vlan_states);
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

  my $v_state = $snmp->v_state || {};

  # get vlan states (required for ignoring suspended vlans)
  while (my ($idx, $state) = each %$v_state) {
      # hack: if vlan id comes as 1.142 instead of 142
      (my $vlan = $idx) =~ s/^\d+\.//;

      # just in case i_vlan is different to v_name set
      # capture the VLAN, but it's not in use on a port
      $vlans{$vlan} ||= 0;

      $vlan_states{$vlan} = $state;
  }

  return sanity_vlans($device, \%vlans, \%vlan_names, \%vlan_states);
}

sub sanity_vlans {
  my ($device, $vlans, $vlan_names, $vlan_states) = @_;

  my @ok_vlans = ();
  foreach my $vlan (sort keys %$vlans) {
      my $name = $vlan_names->{$vlan} || '(unnamed)';
      my $state = $vlan_states->{$vlan} || '(unknown)';

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
      if (not $vlans->{$vlan} and not setting('macsuck_all_vlans')) {
          debug sprintf
            ' [%s] macsuck VLAN %s/%s - not in use by any port - skipping.',
            $device->ip, $vlan, $name;
          next;
      }

      # check if vlan is in state 'suspended'
      if ($state eq 'suspended') {
          debug sprintf
            ' [%s] macsuck VLAN %s - VLAN is suspended - skipping.',
            $device->ip, $vlan;
          next;
      }

      push @ok_vlans, $vlan;
  }

  return @ok_vlans;
}

# walks the forwarding table (BRIDGE-MIB) for the device and returns a
# table of node entries.
sub walk_fwtable {
  my ($snmp, $device, $interfaces, $comm_vlan) = @_;
  my $cache = {};

  my $fw_mac   = $snmp->fw_mac || {};
  my $fw_port  = $snmp->fw_port || {};
  my $fw_vlan  = ($snmp->can('cisco_comm_indexing') and $snmp->cisco_comm_indexing()) 
    ? {} : $snmp->qb_fw_vlan;
  my $bp_index = $snmp->bp_index || {};

  # to map forwarding table port to device port we have
  #   fw_port -> bp_index -> interfaces

  MAC: while (my ($idx, $mac) = each %$fw_mac) {
      my $bp_id = $fw_port->{$idx};
      next unless defined $mac;

      unless (defined $bp_id) {
          debug sprintf
            ' [%s] macsuck %s - %s has no fw_port mapping - skipping.',
            $device->ip, $mac, $idx;
          next MAC;
      }

      my $iid  = $bp_index->{$bp_id};
      my $vlan = $fw_vlan->{$idx} || $comm_vlan || '0';

      unless (defined $iid) {
          debug sprintf
            ' [%s] macsuck %s - port %s has no bp_index mapping - skipping.',
            $device->ip, $mac, $bp_id;
          next MAC;
      }

      # WRT #475 this is SAFE because we check against known ports below
      # but we do need the SNMP interface IDs to get the job done
      my $port = $interfaces->{$iid};

      unless (defined $port) {
          debug sprintf
            ' [%s] macsuck %s - iid %s has no port mapping - skipping.',
            $device->ip, $mac, $iid;
          next MAC;
      }

      ++$cache->{$vlan}->{$port}->{$mac};
  }

  return $cache;
}

sub sanity_macs {
  my ($device, $cache, $device_ports) = @_;

  # note any of the MACs which are actually device or device_port MACs
  # used to spot uplink ports (neighborport)
  my @fw_mac_list = ();
  foreach my $vlan (keys %{ $cache }) {
      foreach my $port (keys %{ $cache->{$vlan} }) {
          push @fw_mac_list, keys %{ $cache->{$vlan}->{$port} };
      }
  }
  @fw_mac_list = List::MoreUtils::uniq( @fw_mac_list );
  my $port_macs = get_port_macs(\@fw_mac_list);

  my $neighborport = {}; # ports through which we can see another device
  my $ignoreport   = {}; # ports suppressed by macsuck_no_deviceports

  if (scalar @{ setting('macsuck_no_deviceports') }) {
      my @ignoremaps = @{ setting('macsuck_no_deviceports') };

      foreach my $map (@ignoremaps) {
          next unless ref {} eq ref $map;

          foreach my $key (sort keys %$map) {
              # lhs matches device, rhs matches port
              next unless $key and $map->{$key};
              next unless acl_matches($device, $key);

              foreach my $port (sort { sort_port($a, $b) } keys %{ $device_ports }) {
                  next unless acl_matches($device_ports->{$port}, $map->{$key});

                  debug sprintf ' [%s] macsuck %s - port suppressed by macsuck_no_deviceports',
                    $device->ip, $port;
                  ++$ignoreport->{$port};
              }
          }
      }
  }


  foreach my $vlan (keys %{ $cache }) {
      foreach my $port (keys %{ $cache->{$vlan} }) {
          MAC: foreach my $mac (keys %{ $cache->{$vlan}->{$port} }) {

              unless (check_mac($mac, $device)) {
                  delete $cache->{$vlan}->{$port}->{$mac};
                  next MAC;
              }

              # this uses the cached $ports resultset to limit hits on the db
              my $device_port = $device_ports->{$port};

              # WRT #475 ... see? :-)
              unless (defined $device_port) {
                  debug sprintf
                    ' [%s] macsuck %s - port %s is not in database - skipping.',
                    $device->ip, $mac, $port;
                  delete $cache->{$vlan}->{$port}->{$mac};
                  next MAC;
              }

              if (exists $ignoreport->{$port}) {
                  debug sprintf
                    ' [%s] macsuck %s - port %s is suppressed by config - skipping.',
                    $device->ip, $mac, $port;
                  delete $cache->{$vlan}->{$port}->{$mac};
                  next MAC;
              }

              if (exists $neighborport->{$port}) {
                  debug sprintf
                    ' [%s] macsuck %s - seen another device thru port %s - skipping.',
                    $device->ip, $mac, $port;
                  delete $cache->{$vlan}->{$port}->{$mac};
                  next MAC;
              }

              # check to see if the port is connected to another device
              # and if we have that device in the database.

              # carefully be aware: "uplink" here means "connected to another device"
              # it does _not_ mean that the user wants nodes gathered on the remote dev.

              # we have two ways to detect "uplink" port status:
              #  * a neighbor was discovered using CDP/LLDP
              #  * a mac addr is seen which belongs to any device port/interface

              # allow to gather MACs on upstream (local) port for some kinds
              # of device that do not expose MAC address tables via SNMP.
              # relies on prefetched neighbors otherwise it would kill the DB
              # with device lookups.

              my $neigh_cannot_macsuck = eval { # can fail
                acl_matches(($device_port->neighbor || "0 but true"), 'macsuck_unsupported') ||
                match_to_setting($device_port->remote_type, 'macsuck_unsupported_type') };

              # here, is_uplink comes from Discover::Neighbors finding LLDP remnants
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
                      delete $cache->{$vlan}->{$port}->{$mac};
                      next MAC;
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

                      $neighborport->{$port} = [ $vlan, $mac ] # remember neighbor port mac
                        if exists $port_macs->{$mac};
                      delete $cache->{$vlan}->{$port}->{$mac};
                      next MAC;
                  }
              }

              # here, the MAC is known as belonging to a device switchport
              if (exists $port_macs->{$mac}) {
                  my $switch_ip = $port_macs->{$mac};
                  if ($device->ip eq $switch_ip) {
                      debug sprintf
                        ' [%s] macsuck %s - port %s connects to self - skipping.',
                        $device->ip, $mac, $port;
                      delete $cache->{$vlan}->{$port}->{$mac};
                      next MAC;
                  }

                  debug sprintf ' [%s] macsuck %s - port %s is probably an uplink',
                    $device->ip, $mac, $port;
                  $device_port->update({is_uplink => \'true'});

                  if ($neigh_cannot_macsuck) {
                      # neighbor exists and Netdisco can speak to it, so we don't want
                      # its MAC address. however don't add to neighborport as that would
                      # clear all other MACs on the port.
                      delete $cache->{$vlan}->{$port}->{$mac};
                      next MAC;
                  }

                  # when there's no CDP/LLDP, we only want to gather macs at the
                  # topology edge, hence skip ports with known device macs.
                  if (not setting('macsuck_bleed')) {
                        debug sprintf ' [%s] macsuck %s - port %s is at topology edge',
                            $device->ip, $mac, $port;

                        $neighborport->{$port} = [ $vlan, $mac ]; # remember for later
                        delete $cache->{$vlan}->{$port}->{$mac};
                        next MAC;
                  }
              }

              # possibly move node to lag master
              if (defined $device_port->slave_of
                    and exists $device_ports->{$device_port->slave_of}) {

                  my $parent = $device_port->slave_of;
                  $device_ports->{$parent}->update({is_uplink => \'true'});

                  # VLAN subinterfaces can be set uplink,
                  # but we don't want to move nodes there (so check is_master).
                  if ($device_ports->{$parent}->is_master) {
                      delete $cache->{$vlan}->{$port}->{$mac};
                      ++$cache->{$vlan}->{$parent}->{$mac};
                  }
              }
          }
      }
  }

  # restore MACs of neighbor devices.
  # this is when we have a "possible uplink" detected but we still want to
  # record the single MAC of the neighbor device so it works in Node search.
  foreach my $port (keys %$neighborport) {
      my ($vlan, $mac) = @{ $neighborport->{$port} };
      delete $cache->{$_}->{$port} for keys %$cache; # nuke nodes on all VLANs
      ++$cache->{$vlan}->{$port}->{$mac};
  }

  return $cache;
}

true;
