package App::Netdisco::Worker::Plugin::Discover::Neighbors;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Device
  qw/get_device match_devicetype is_discoverable/;
use App::Netdisco::Util::Permission 'check_acl_no';
use App::Netdisco::JobQueue 'jq_insert';
use Dancer::Plugin::DBIC 'schema';
use List::MoreUtils ();
use NetAddr::MAC;
use Encode;
use Try::Tiny;

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
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my @to_discover = store_neighbors($device);
  my %seen_id = ();

  # only enqueue if device is not already discovered,
  # discover_* config permits the discovery
  foreach my $neighbor (@to_discover) {
      my ($ip, $remote_type, $remote_id) = @$neighbor;
      if ($remote_id and $seen_id{ $remote_id }++) {
          debug sprintf
            ' queue - skip: %s with ID [%s] already queued from %s',
            $ip, $remote_id, $device->ip;
          next;
      }

      my $device = get_device($ip);
      next if $device->in_storage;

      if (not is_discoverable($device, $remote_type)) {
          debug sprintf
            ' queue - skip: %s of type [%s] excluded by discover_* config',
            $ip, ($remote_type || '');
          next;
      }

      # risk of things going wrong...?
      # https://quickview.cloudapps.cisco.com/quickview/bug/CSCur12254

      jq_insert({
        device => $ip,
        action => 'discover',
        subaction => 'with-nodes',
        ($remote_id ? (device_key => $remote_id) : ()),
      });
  }

  return Status->info(sprintf ' [%s] neigh - processed %s neighbors',
       $device->ip, scalar @to_discover);
});

=head2 store_neighbors( $device )

returns: C<@to_discover>

Given a Device database object, and a working SNMP connection, discover and
store the device's port neighbors information.

Entries in the Topology database table will override any discovered device
port relationships.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

A list of discovererd neighbors will be returned as [C<$ip>, C<$type>] tuples.

=cut

sub store_neighbors {
  my $device = shift;
  my @to_discover = ();

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return (); # already checked!

  # first allow any manually configured topology to be set
  set_manual_topology($device);

  if (!defined $snmp->has_topo) {
      debug sprintf ' [%s] neigh - neighbor protocols are not enabled', $device->ip;
      return @to_discover;
  }

  my $interfaces = $snmp->interfaces;
  my $c_if       = $snmp->c_if;
  my $c_port     = $snmp->c_port;
  my $c_id       = $snmp->c_id;
  my $c_platform = $snmp->c_platform;
  my $c_cap      = $snmp->c_cap;

  # v4 and v6 neighbor tables
  my $c_ip = ($snmp->c_ip || {});
  my %c_ipv6 = %{ ($snmp->can('hasLLDP') and $snmp->hasLLDP)
    ? ($snmp->lldp_ipv6 || {}) : {} };

  # remove keys with undef values, as c_ip does
  delete @c_ipv6{ grep { not defined $c_ipv6{$_} } keys %c_ipv6 };
  # now combine them, v6 wins
  $c_ip = { %$c_ip, %c_ipv6 };

  foreach my $entry (sort (List::MoreUtils::uniq( (keys %$c_ip), (keys %$c_cap) ))) {
      if (!defined $c_if->{$entry} or !defined $interfaces->{ $c_if->{$entry} }) {
          debug sprintf ' [%s] neigh - port for IID:%s not resolved, skipping',
            $device->ip, $entry;
          next;
      }

      my $port = $interfaces->{ $c_if->{$entry} };
      my $portrow = schema('netdisco')->resultset('DevicePort')
          ->single({ip => $device->ip, port => $port});

      if (!defined $portrow) {
          info sprintf ' [%s] neigh - local port %s not in database!',
            $device->ip, $port;
          next;
      }

      if (ref $c_ip->{$entry}) {
          error sprintf ' [%s] neigh - Error! port %s has multiple neighbors - skipping',
            $device->ip, $port;
          next;
      }

      my $remote_ip   = $c_ip->{$entry};
      my $remote_port = undef;
      my $remote_type = Encode::decode('UTF-8', $c_platform->{$entry} || '');
      my $remote_id   = Encode::decode('UTF-8', $c_id->{$entry});
      my $remote_cap  = $c_cap->{$entry} || [];

      # IP Phone and WAP detection type fixup
      if (scalar @$remote_cap or $remote_type) {
          my $phone_flag = grep {match_devicetype($_, 'phone_capabilities')}
                                @$remote_cap;
          my $ap_flag    = grep {match_devicetype($_, 'wap_capabilities')}
                                @$remote_cap;

          if ($phone_flag or match_devicetype($remote_type, 'phone_platforms')) {
              $remote_type = 'IP Phone: '. $remote_type
                if $remote_type !~ /ip.phone/i;
          }
          elsif ($ap_flag or match_devicetype($remote_type, 'wap_platforms')) {
              $remote_type = 'AP: '. $remote_type;
          }

          $portrow->update({remote_type => $remote_type});
      }

      if ($portrow->manual_topo) {
          info sprintf ' [%s] neigh - %s has manually defined topology',
            $device->ip, $port;
          next;
      }

      next unless $remote_ip;

      # a bunch of heuristics to search known devices if we don't have a
      # useable remote IP...

      if ($remote_ip eq '0.0.0.0' or
        check_acl_no($remote_ip, 'group:__LOCAL_ADDRESSES__')) {

          if ($remote_id) {
              my $devices = schema('netdisco')->resultset('Device');
              my $neigh = $devices->single({name => $remote_id});
              info sprintf
                ' [%s] neigh - bad address %s on port %s, searching for %s instead',
                $device->ip, $remote_ip, $port, $remote_id;

              if (!defined $neigh) {
                  my $mac = NetAddr::MAC->new(mac => $remote_id);
                  if ($mac and not $mac->errstr) {
                      $neigh = $devices->single({mac => $mac->as_ieee});
                  }
              }

              # some HP switches send 127.0.0.1 as remote_ip if no ip address
              # on default vlan for HP switches remote_ip looks like
              # "myswitchname(012345-012345)"
              if (!defined $neigh) {
                  (my $tmpid = $remote_id) =~ s/.*\(([0-9a-f]{6})-([0-9a-f]{6})\).*/$1$2/;
                  my $mac = NetAddr::MAC->new(mac => $tmpid);
                  if ($mac and not $mac->errstr) {
                      info sprintf
                        '[%s] neigh - found neighbor %s by MAC %s',
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
                  info sprintf ' [%s] neigh - found %s with IP %s',
                    $device->ip, $remote_id, $remote_ip;
              }
              else {
                  info sprintf ' [%s] neigh - could not find %s, skipping',
                    $device->ip, $remote_id;
                  next;
              }
          }
          else {
              info sprintf ' [%s] neigh - skipping unuseable address %s on port %s',
                $device->ip, $remote_ip, $port;
              next;
          }
      }

      # what we came here to do.... discover the neighbor
      debug sprintf
        ' [%s] neigh - adding neighbor %s, type [%s], on %s to discovery queue',
        $device->ip, $remote_ip, ($remote_type || ''), $port;
      push @to_discover, [$remote_ip, $remote_type, $remote_id];

      $remote_port = $c_port->{$entry};
      if (defined $remote_port) {
          # clean weird characters
          $remote_port =~ s/[^\d\/\.,()\w:-]+//gi;
      }
      else {
          info sprintf ' [%s] neigh - no remote port found for port %s at %s',
            $device->ip, $port, $remote_ip;
      }

      $portrow->update({
          remote_ip   => $remote_ip,
          remote_port => $remote_port,
          remote_type => $remote_type,
          remote_id   => $remote_id,
          is_uplink   => \"true",
          manual_topo => \"false",
      });

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
                  is_uplink => \"true",
                  is_master => \"true",
                  manual_topo => \"false",
              });
          }
      }
  }

  return @to_discover;
}

# take data from the topology table and update remote_ip and remote_port
# in the devices table. only use root_ips and skip any bad topo entries.
sub set_manual_topology {
  my $device = shift;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device) or return;

  schema('netdisco')->txn_do(sub {
    # clear manual topology flags
    schema('netdisco')->resultset('DevicePort')
      ->search({ip => $device->ip})->update({manual_topo => \'false'});

    my $topo_links = schema('netdisco')->resultset('Topology')
      ->search({-or => [dev1 => $device->ip, dev2 => $device->ip]});
    debug sprintf ' [%s] neigh - setting manual topology links', $device->ip;

    while (my $link = $topo_links->next) {
        # could fail for broken topo, but we ignore to try the rest
        try {
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
            });
        };
    }
  });
}

true;
