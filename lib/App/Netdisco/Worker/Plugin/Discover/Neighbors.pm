package App::Netdisco::Worker::Plugin::Discover::Neighbors;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Device qw/get_device is_discoverable match_to_setting/;
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::JobQueue 'jq_insert';
use Dancer::Plugin::DBIC 'schema';
use List::Util 'pairs';
use NetAddr::IP::Lite ();
use NetAddr::MAC;
use App::Netdisco::Util::SNMPText 'decode_snmp_text';
use App::Netdisco::Util::SNMP qw/walk_mark incomplete_walks_for incomplete_walk_message
  incomplete_walk_level/;
use Try::Tiny;

my @neighbor_walks = qw/has_topo c_if c_port c_id c_ip c_platform c_cap lldp_ipv6 interfaces/;

=head2 discover_new_neighbors( )

Given a Device database object, and a working SNMP connection, discover and
store the device's port neighbors information.

Entries in the Topology database table will override any discovered device
port relationships.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

Any discovered neighbor unknown to Netdisco will have a C<discover> job
immediately queued (subject to the filtering by the C<discover_*> settings).

=cut

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;

  if (acl_matches($device, 'skip_neighbors') or not setting('discover_neighbors')) {
      clear_neighbor_columns($device, [], include_manual => 1);
      return Status->info(
        sprintf ' [%s] neigh - neighbor discovery is disabled on this device',
        $device->ip);
  }

  if (not setting('queue_neighbors')) {
      config->{'discover_only'} = $device->ip;
      debug sprintf ' [%s] neigh - neighbors will be discovered but not queued',
        $device->ip;
  }

  # do not remove. not used directly in this worker
  # but is used in store_neighbors()
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  # store_neighbors() will update neighbors on ports, in the database
  # might return empty set if config or other reasons deny neighbor discovery
  my @incomplete = ();
  my @to_discover = store_neighbors($device, \@incomplete);
  my (%seen_id, %seen_ip) = ((), ());

  # only enqueue if device is not already discovered,
  # discover_* config permits the discovery
  foreach my $neighbor (@to_discover) {
      my ($ip, $remote_id) = @$neighbor;
      if ($seen_ip{ $ip }++) {
          debug sprintf
            ' queue - skip: IP %s is already queued from %s',
            $ip, $device->ip;
          next;
      }

      if ($remote_id and $seen_id{ $remote_id }++) {
          debug sprintf
            ' queue - skip: %s with ID [%s] already queued from %s',
            $ip, $remote_id, $device->ip;
          next;
      }

      my $newdev = get_device($ip);
      next if $newdev->in_storage;

      # risk of things going wrong...?
      # https://quickview.cloudapps.cisco.com/quickview/bug/CSCur12254

      jq_insert({
        device => $ip,
        action => 'discover',
        ($remote_id ? (device_key => $remote_id) : ()),
      });

      vars->{'queued'}->{$ip} = true;
      debug sprintf ' [%s] queue - queued %s for discovery (ID: [%s])',
        $device, $ip, ($remote_id || '');
  }

  my $processed = sprintf ' [%s] neigh - processed %s neighbors',
    $device->ip, scalar @to_discover;

  if (scalar @incomplete) {
      my $message = incomplete_walk_message($device, 'neigh', @incomplete);
      my $level = incomplete_walk_level(@incomplete);
      warning $message;
      return Status->$level("$processed; $message");
  }

  return Status->info($processed);
});

=head2 store_neighbors( $device, \@incomplete? )

returns: C<@to_discover>

Given a Device database object, and a working SNMP connection, discover and
store the device's port neighbors information.

Entries in the Topology database table will override any discovered device
port relationships.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

A list of discovered neighbors will be returned as [C<$ip>, C<$type>] tuples.

Neighbor columns are cleared on the device's other ports, unless a neighbor
walk was incomplete. Those walk outcomes are pushed onto C<@incomplete> when
it is given.

=cut

sub store_neighbors {
  my ($device, $incomplete) = @_;
  $incomplete ||= [];
  my @to_discover = ();
  my %written = ();

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return (); # already checked!

  # first allow any manually configured topology to be set;
  # this will also bust the cache in vars->{'device_ports'}
  set_manual_topology($device);
  my $walk_mark = walk_mark($snmp);

  if (!defined $snmp->has_topo) {
      debug sprintf ' [%s] neigh - neighbor protocols are not enabled', $device->ip;
      push @$incomplete, incomplete_walks_for($device, $snmp, $walk_mark, 'has_topo');
      clear_neighbor_columns($device, []) if not scalar @$incomplete;
      return @to_discover;
  }

  my $interfaces = $snmp->interfaces;
  my $c_if       = $snmp->c_if;
  my $c_port     = $snmp->c_port;
  my $c_id       = $snmp->c_id;
  my $c_platform = $snmp->c_platform;
  my $c_cap      = $snmp->c_cap;

  # cache the device ports to save hitting the database for many single rows
  my $device_ports = vars->{'device_ports'}
    || { map {($_->port => $_)} $device->ports->all };

  # v4 and v6 neighbor tables
  my $c_ip = ($snmp->c_ip || {});
  my %c_ipv6 = %{ ($snmp->can('hasLLDP') and $snmp->hasLLDP)
    ? ($snmp->lldp_ipv6 || {}) : {} };

  # remove keys with undef values, as c_ip does
  delete @c_ipv6{ grep { not defined $c_ipv6{$_} } keys %c_ipv6 };

  # neighbors found by a cut-short walk are still written, but a port missing
  # from it may only have been missed, so nothing is cleared
  push @$incomplete, incomplete_walks_for($device, $snmp, $walk_mark, @neighbor_walks);

  # allow fallback from v6 to try v4
  my %success_with_index = ();

  NEIGHBOR: foreach my $pair ((sort { $a->key cmp $b->key } pairs %c_ipv6),
                              (sort { $a->key cmp $b->key } pairs %$c_ip)) {

      my ($entry, $c_ip_entry) = (@$pair);
      next unless defined $entry and defined $c_ip_entry;

      if (!defined $c_if->{$entry} or !defined $interfaces->{ $c_if->{$entry} }) {
          debug sprintf ' [%s] neigh - port for IID:%s not resolved, skipping',
            $device->ip, $entry;
          next NEIGHBOR;
      }

      # WRT #475 this is SAFE because we check against known ports below
      my $port = $interfaces->{ $c_if->{$entry} } or next NEIGHBOR;
      my $portrow = $device_ports->{$port};

      if (!defined $portrow) {
          debug sprintf ' [%s] neigh - local port %s already skipped, ignoring',
            $device->ip, $port;
          next NEIGHBOR;
      }

      if (ref $c_ip_entry) {
          debug sprintf ' [%s] neigh - port %s has multiple neighbors - skipping',
            $device->ip, $port;
          next NEIGHBOR;
      }

      if ($portrow->manual_topo) {
          debug sprintf ' [%s] neigh - %s has manually defined topology',
            $device->ip, $port;
          next NEIGHBOR;
      }

      my $remote_ip   = $c_ip_entry;
      my $remote_port = undef;
      my $remote_type = decode_snmp_text($c_platform->{$entry} || '', $device, "neighbor $port remote_type");
      my $remote_id   = decode_snmp_text($c_id->{$entry}, $device, "neighbor $port remote_id");
      my $remote_cap  = $c_cap->{$entry} || [];

      next NEIGHBOR unless $remote_ip;
      my $r_netaddr = NetAddr::IP::Lite->new($remote_ip);

      if ($r_netaddr and ($r_netaddr->addr ne $remote_ip)) {
        debug sprintf ' [%s] neigh - IP on %s: using %s as canonical form of %s',
          $device->ip, $port, $r_netaddr->addr, $remote_ip;
        $remote_ip = $r_netaddr->addr;
      }

      if ($remote_ip and acl_matches($remote_ip, 'group:__LOCAL_ADDRESSES__')) {
          debug sprintf ' [%s] neigh - %s is a non-unique local address - skipping',
            $device->ip, $remote_ip;
          next NEIGHBOR;
      }

      if ($remote_type and match_to_setting($remote_type, 'neighbor_no_type')) {
          debug sprintf ' [%s] neigh - %s has type %s matching neighbor_no_type - skipping',
            $device->ip, $remote_ip, $remote_type;
          next NEIGHBOR;
      }

      # a bunch of heuristics to search known devices if we do not have a
      # useable remote IP...

      if ((! $r_netaddr) or ($remote_ip eq '0.0.0.0') or
        acl_matches($remote_ip, 'group:__LOOPBACK_ADDRESSES__')) {

          if ($remote_id) {
              my $devices = schema('netdisco')->resultset('Device');

              debug sprintf
                ' [%s] neigh - bad address %s on port %s, searching for %s instead',
                $device->ip, $remote_ip, $port, $remote_id;
              my $neigh_rs = $devices->search_rs({name => $remote_id});
              my $neigh = ($neigh_rs->count == 1 ? $neigh_rs->first : undef);

              if (!defined $neigh and $neigh_rs->count) {
                  debug sprintf ' [%s] neigh - multiple devices claim to be %s (port %s) - skipping',
                    $device->ip, $remote_id, $port;
                  next NEIGHBOR;
              }

              if (!defined $neigh) {
                  my $mac = NetAddr::MAC->new(mac => ($remote_id || ''));
                  if ($mac and not $mac->errstr) {
                      $neigh = $devices->single({mac => $mac->as_ieee});
                  }
              }

              # some HP switches send 127.0.0.1 as remote_ip if no ip address
              # on default vlan for HP switches remote_ip looks like
              # "myswitchname(012345-012345)"
              if (!defined $neigh) {
                  (my $tmpid = $remote_id) =~ s/.*\(([0-9a-f]{6})-([0-9a-f]{6})\).*/$1$2/;
                  my $mac = NetAddr::MAC->new(mac => ($tmpid || ''));
                  if ($mac and not $mac->errstr) {
                      debug sprintf
                        ' [%s] neigh - trying to find neighbor %s by MAC %s',
                        $device->ip, $remote_id, $mac->as_ieee;
                      $neigh = $devices->single({mac => $mac->as_ieee});
                  }
              }

              if (!defined $neigh) {
                  (my $shortid = $remote_id) =~ s/\..*//;
                  $neigh = $devices->single({name => { -ilike => "${shortid}%" }});
              }

              if ($neigh) {
                  $remote_ip = $neigh->ip;
                  debug sprintf ' [%s] neigh - found %s with IP %s',
                    $device->ip, $remote_id, $remote_ip;
              }
              else {
                  debug sprintf ' [%s] neigh - could not find %s, skipping',
                    $device->ip, $remote_id;
                  next NEIGHBOR;
              }
          }
          else {
              debug sprintf ' [%s] neigh - skipping unuseable address %s on port %s',
                $device->ip, $remote_ip, $port;
              next NEIGHBOR;
          }
      }

      if (++$success_with_index{$entry} > 1) {
          debug sprintf ' [%s] neigh - port for IID:%s already got a neighbor, skipping',
            $device->ip, $entry;
          next NEIGHBOR;
      }

      # what we came here to do.... discover the neighbor
      debug sprintf ' [%s] neigh - %s with ID [%s] on %s',
        $device->ip, $remote_ip, ($remote_id || ''), $port;

      if (is_discoverable($remote_ip, $remote_type, $remote_cap)) {
          push @to_discover, [$remote_ip, $remote_id];
      }
      else {
          debug sprintf
            ' [%s] neigh - skip: %s of type [%s] excluded by discover_* config',
            $device->ip, $remote_ip, ($remote_type || '');
      }

      $remote_port = $c_port->{$entry};
      if (defined $remote_port) {
          # clean weird characters
          $remote_port =~ s/[^\d\s\/\.,"()\w:-]+//gi;
      }
      else {
          debug sprintf ' [%s] neigh - no remote port found for port %s at %s',
            $device->ip, $port, $remote_ip;
      }

      $portrow = $portrow->update({
          remote_ip   => $remote_ip,
          remote_port => $remote_port,
          remote_type => $remote_type,
          remote_id   => $remote_id,
          is_uplink   => \"true",
          manual_topo => \"false",
      })->discard_changes();
      $written{$port} = 1;

      # update master of our aggregate to be a neighbor of
      # the master on our peer device (a lot of iffs to get there...).
      # & cannot use ->neighbor prefetch because this is the port insert!
      if (defined $portrow->slave_of) {

          my $peer_device = get_device($remote_ip);
          my $master = schema('netdisco')->resultset('DevicePort')->single({
            ip => $device->ip,
            port => $portrow->slave_of
          });

          if ($peer_device and $peer_device->in_storage and $master
              and not ($portrow->is_master or defined $master->slave_of)) {

              my $peer_port = schema('netdisco')->resultset('DevicePort')->single({
                ip   => $peer_device->ip,
                port => $portrow->remote_port,
              });

              $master->update({
                  remote_ip => ($peer_device->ip || $remote_ip),
                  remote_port => ($peer_port ? $peer_port->slave_of : undef ),
                  remote_type => undef,
                  remote_id   => undef,
                  is_uplink => \"true",
                  is_master => \"true",
                  manual_topo => \"false",
              });
              $written{ $master->port } = 1;
          }
      }
  }

  clear_neighbor_columns($device, [keys %written]) if not scalar @$incomplete;
  return @to_discover;
}

=head2 clear_neighbor_columns( $device, \@keep_ports, %opt )

Clears C<remote_*> and C<is_uplink> on the device's ports not named in
C<@keep_ports>, in one statement that writes only rows not already clear.
Ports with C<manual_topo> are left alone, unless C<include_manual> is set,
when they are cleared too and C<manual_topo> is set false.

=cut

sub clear_neighbor_columns {
  my ($device, $keep_ports, %opt) = @_;

  my %where = (
    ip => $device->ip,
    (scalar @$keep_ports ? (port => { -not_in => [sort @$keep_ports] }) : ()),
    ($opt{include_manual} ? () : (-not_bool => 'manual_topo')),
    -or => [
      (map {{ $_ => { '!=' => undef } }} qw/remote_ip remote_port remote_type remote_id/),
      { is_uplink => \'IS TRUE' },
      ($opt{include_manual} ? { -bool => 'manual_topo' } : ()),
    ],
  );

  my $cleared = schema('netdisco')->resultset('DevicePort')->search(\%where)->update({
    remote_ip   => undef,
    remote_port => undef,
    remote_type => undef,
    remote_id   => undef,
    is_uplink   => undef,
    ($opt{include_manual} ? (manual_topo => \'false') : ()),
  });

  # later workers read remote_ip from the cached rows; store_column leaves
  # them clean, so no later update writes these columns again
  my %keep = map {($_ => 1)} @$keep_ports;
  foreach my $row (values %{ vars->{'device_ports'} || {} }) {
      next if $keep{ $row->port } or ($row->manual_topo and not $opt{include_manual});
      $row->store_column($_ => undef) for qw/remote_ip remote_port remote_type remote_id is_uplink/;
      $row->store_column(manual_topo => 0) if $opt{include_manual};
  }

  return $cleared;
}

# take data from the topology table and update remote_ip and remote_port
# in the devices table. only use root_ips and skip any bad topo entries.
sub set_manual_topology {
  my $device = shift;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device) or return;

  # clear outdated manual topology links
  my $old_links = schema('netdisco')->resultset('Topology')->search({
    -or => [
      { dev1 => $device->ip,
        port1 => { '-not_in' => $device->ports->get_column('port')->as_query } },
      { dev2 => $device->ip,
        port2 => { '-not_in' => $device->ports->get_column('port')->as_query } },
    ],
  })->delete;
  debug sprintf ' [%s] neigh - removed %d outdated manual topology links',
    $device->ip, $old_links;

  my $topo_links = schema('netdisco')->resultset('Topology')
    ->search({-or => [dev1 => $device->ip, dev2 => $device->ip]});
  debug sprintf ' [%s] neigh - setting manual topology links', $device->ip;

  my %manual = ();
  # each link commits on its own: holding one link's port rows while
  # locking the next could deadlock with that peer's own discover
  while (my $link = $topo_links->next) {
      # could fail for broken topo, but we ignore to try the rest
      try {
          # recorded only once the link's transaction commits, since a
          # failed right side rolls the left side back
          my @own_ports = ();
          schema('netdisco')->txn_do(sub {
            # only work on root_ips
            my $left  = get_device($link->dev1);
            my $right = get_device($link->dev2);

            # skip bad entries
            return unless ($left->in_storage and $right->in_storage);

            $left->ports
              ->single({port => $link->port1})
              ->update({
                remote_ip => $right->ip,
                remote_port => $link->port2,
                remote_type => undef,
                remote_id   => undef,
                is_uplink   => \"true",
                manual_topo => \"true",
              });
            push @own_ports, $link->port1 if $left->ip eq $device->ip;

            $right->ports
              ->single({port => $link->port2})
              ->update({
                remote_ip => $left->ip,
                remote_port => $link->port1,
                remote_type => undef,
                remote_id   => undef,
                is_uplink   => \"true",
                manual_topo => \"true",
              });
            push @own_ports, $link->port2 if $right->ip eq $device->ip;
          });
          $manual{$_} = 1 for @own_ports;
      };
  }

  # clear manual topology flags left from links that are gone
  schema('netdisco')->resultset('DevicePort')->search({
    ip => $device->ip,
    -bool => 'manual_topo',
    (scalar keys %manual ? (port => { -not_in => [sort keys %manual] }) : ()),
  })->update({manual_topo => \'false'});

  # bust the cache after updating manual topology.
  vars->{'device_ports'} = { map {($_->port => $_)}
                                 $device->ports(undef, {prefetch => 'properties'})->reset->all };
}

true;
