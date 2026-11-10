package App::Netdisco::Util::Node;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use NetAddr::MAC;
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;
use App::Netdisco::Util::VRF qw/vrf_collection_enabled vrf_skip_test/;
use App::Netdisco::Util::L3Domain qw/recompute_l3_domains l3_domain_recompute_needed/;
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  check_mac
  is_nbtstatable
  memoize_arp
  store_arp
  retire_unvouched_arps
  record_cli_vrfs
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# excluding the target row from the retire in store_arp lets two pollers that
# report one IP under different MACs deadlock, so each entry first takes this
# class keyed by its host IP; retire_unvouched_arps takes it keyed by the router
# IP, and a key shared by a host and a router only serializes the two. Class
# 1729 (key 0) guards L3 domain writes: see App::Netdisco::Util::L3Domain
my $ARP_LOCK_CLASS = 1728;

=head1 NAME

App::Netdisco::Util::Node

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 check_mac( $node, $device?, $port_macs? )

Given a MAC address, perform various sanity checks which need to be done
before writing an ARP/Neighbor entry to the database storage.

Returns false, and might log a debug level message, if the checks fail.

Returns a true value (the MAC address in IEEE format) if these checks pass:

=over 4

=item *

MAC address is well-formed (according to common formats)

=item *

MAC address is not all-zero, broadcast, CLIP, VRRP or HSRP

=back

Optionally pass a Device instance or IP to use in logging.

Optionally pass a cached set of Device port MAC addresses as the third
argument, in which case an additional check is added:

=over 4

=item *

MAC address does not belong to an interface on any known Device

=back

=cut

sub check_mac {
  my ($node, $device, $port_macs) = @_;
  return 0 if !$node;

  my $mac = NetAddr::MAC->new(mac => ($node || ''));
  my $devip = ($device ? (ref $device ? $device->ip : $device) : '');
  $port_macs ||= {};

  # incomplete MAC addresses (BayRS frame relay DLCI, etc)
  if (!defined $mac or $mac->errstr) {
      debug sprintf ' [%s] check_mac - mac [%s] malformed - skipping',
        $devip, $node;
      return 0;
  }
  else {
      # lower case, hex, colon delimited, 8-bit groups
      $node = lc $mac->as_ieee;
  }

  # broadcast MAC addresses
  return 0 if $mac->is_broadcast;

  # all-zero MAC addresses
  return 0 if $node eq '00:00:00:00:00:00';

  # CLIP
  return 0 if $node eq '00:00:00:00:00:01';

  # multicast
  if ($mac->is_multicast and not $mac->is_msnlb) {
      debug sprintf ' [%s] check_mac - multicast mac [%s] - skipping',
        $devip, $node;
      return 0;
  }

  # VRRP
  if ($mac->is_vrrp) {
      debug sprintf ' [%s] check_mac - VRRP mac [%s] - skipping',
        $devip, $node;
      return 0;
  }

  # HSRP
  if ($mac->is_hsrp or $mac->is_hsrp2) {
      debug sprintf ' [%s] check_mac - HSRP mac [%s] - skipping',
        $devip, $node;
      return 0;
  }

  # device's own MACs
  if ($port_macs and exists $port_macs->{$node}) {
      debug sprintf ' [%s] check_mac - mac [%s] is device port - skipping',
        $devip, $node;
      return 0;
  }

  return $node;
}

=head2 is_nbtstatable( $ip )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to nbtstat the node.

The configuration items C<nbtstat_no> and C<nbtstat_only> are checked
against the given IP.

Returns false if the host is not permitted to nbtstat the target node.

=cut

sub is_nbtstatable {
  my $ip = shift;

  return if acl_matches($ip, 'nbtstat_no');

  return unless acl_matches_only($ip, 'nbtstat_only');

  return 1;
}

=head2 memoize_arp ( \%host )

Returns a unique string to memoize the arp entry, using node or mac keys,
the ip key and the VRF (an absent VRF reads as the empty string).

=cut

sub memoize_arp {
  my $host = shift or return;
  no warnings 'uninitialized';
  return join chr(28), map {$host->{$_}}
    (($host->{node} ? 'node' : 'mac'), 'ip', 'vrf');
}

=head2 store_arp( \%host, $now?, $device_ip )

Stores a new entry to the C<node_ip> table with the given MAC, IP (v4 or v6)
and DNS host name. Host details are provided in a Hash ref:

 {
    ip   => '192.0.2.1',
    node => '00:11:22:33:44:55',
    dns  => 'myhost.example.com',
 }

The C<dns> entry is optional. The update will mark other active entries for
this IP in the same VRF as no longer C<active>.

Optionally a literal string can be passed in the second argument for the
C<time_last> timestamp, otherwise the current timestamp (C<LOCALTIMESTAMP>) is used.

On which L3 devices an arp entry was found is tracked in the
C<seen_on_router_first> and C<seen_on_router_last> fields of the C<node_ip>.
They contain a timestamp for the time window each router this entry was ever
found on.

=cut

sub store_arp {
  my ($hash_ref, $now, $device_ip) = @_;
  $now ||= 'LOCALTIMESTAMP';
  my $ip   = $hash_ref->{'ip'};
  my $mac  = NetAddr::MAC->new(mac => ($hash_ref->{'node'} || $hash_ref->{'mac'} || ''));
  my $vrf  = $hash_ref->{'vrf'} // '';
  my $name = $hash_ref->{'dns'};

  return if !defined $mac or $mac->errstr;
  warning sprintf 'store_arp - deprecated usage, should be store_arp($hash_ref, $now, $device_ip)' unless $device_ip;
  debug sprintf 'store_arp - device %s mac %s ip %s vrf "%s"', $device_ip // "n/a", $mac->as_ieee, $ip, $vrf;

  my @key = ($mac->as_ieee, $ip, $vrf);
  my ($upsert, @upsert_binds) = _arp_upsert_sql($now, $device_ip);

  schema(vars->{'tenant'})->txn_do(sub {
    schema(vars->{'tenant'})->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->do('SELECT pg_advisory_xact_lock(?, hashtext(host(?::inet)))',
        undef, $ARP_LOCK_CLASS, $ip);
      $dbh->do('UPDATE node_ip SET active = false'
        .' WHERE ip = ? AND vrf = ? AND active AND mac <> ?', undef, $ip, $vrf, $key[0]);
      $dbh->do($upsert, undef, @key, $name, @upsert_binds);
    });
  });
}

# time_last never moves back: an older overlapping job of one router must not
# lower a row the newer job's retire_unvouched_arps will test
# without a router (the deprecated sshcollector call) the maps and router_last
# are left alone
sub _arp_upsert_sql {
  my ($now, $device_ip) = @_;
  my $new_map = ($device_ip ? "jsonb_build_object(?::text, $now)" : q{'{}'::jsonb});
  my $router_column = ($device_ip ? ', router_last' : '');
  my $router_value  = ($device_ip ? ', ?::inet' : '');
  my $sql = qq{INSERT INTO node_ip AS n
      (mac, ip, vrf, dns, active, time_first, time_last, seen_on_router_first, seen_on_router_last$router_column)
    VALUES (?, ?, ?, ?, true, $now, $now, $new_map, $new_map$router_value)
    ON CONFLICT (mac, ip, vrf) DO UPDATE
      SET active = true, dns = EXCLUDED.dns, time_last = GREATEST(n.time_last, EXCLUDED.time_last)};
  return $sql unless $device_ip;

  $sql .= qq{,
        router_last = EXCLUDED.router_last,
        seen_on_router_last = jsonb_set(n.seen_on_router_last, ?, to_jsonb($now)),
        seen_on_router_first = CASE WHEN (n.seen_on_router_first -> ?) IS NOT NULL
          THEN n.seen_on_router_first
          ELSE jsonb_set(n.seen_on_router_first, ?, to_jsonb($now))
        END};
  my $path = "{$device_ip}";
  return ($sql, $device_ip, $device_ip, $device_ip, $path, $device_ip, $path);
}

=head2 record_cli_vrfs( $device, \%vrf_read, $list_complete, $now )

Records in C<device_vrf> each named VRF a CLI collector read (the keys of
C<\%vrf_read>, netdisco names, C<''> skipped), so that it gets an L3 domain
when SNMP::Info does not list it. Rows are C<listed_by> C<cli> and written
only when new, so a row discover wrote keeps its facts. When the collector's
list was whole, the device's C<cli> rows for VRFs it no longer read are
deleted; other rows never are. Domains are recomputed when anything changed.
Returns the number of rows inserted or deleted.

=cut

my @cli_vrf_insert_only = qw/kind rd rt_import rt_export l3_isid listed_by complete last_discover/;

sub record_cli_vrfs {
  my ($device, $vrf_read, $list_complete, $now) = @_;
  my @names = sort grep { length } keys %{ $vrf_read || {} };
  my $rs = schema(vars->{'tenant'})->resultset('DeviceVrf');

  my $changed = (not @names) ? 0 : $rs->upsert([ map {{
    ip => $device->ip, vrf => $_, kind => 'vrf', rd => undef, rt_import => [], rt_export => [],
    l3_isid => undef, listed_by => 'cli', complete => ($vrf_read->{$_} ? 1 : 0),
    last_discover => \$now,
  }} @names ], { insert_only => [@cli_vrf_insert_only] });

  if ($list_complete) {
    my $gone = $rs->search({ ip => $device->ip, listed_by => 'cli',
                             vrf => { -not_in => \@names } })->delete;
    $changed += ($gone eq '0E0' ? 0 : $gone);
  }
  my $schema = schema(vars->{'tenant'});
  try { recompute_l3_domains($schema) if l3_domain_recompute_needed($schema, $changed, 'by arpnip') }
  catch { warning sprintf ' [%s] arpnip - L3 domain recompute failed, the next discover that finds a change retries: %s',
    $device->ip, $_ };
  return $changed;
}

=head2 retire_unvouched_arps( $device, $now, \%vrf_read?, $vrf_list_complete? )

After a complete arpnip of C<$device>, deactivates the active C<node_ip> rows
this router was the last to report (C<router_last>) and did not report in
this run (C<time_last> before C<$now>, the timestamp given to C<store_arp>).
Rows another router reported since name that router and stay; rows with no
C<router_last> are never matched.

With VRF collection off for the device (C<vrf_collection_enabled> in
L<App::Netdisco::Util::VRF>), only rows in named VRFs are retired, never the
default table. With it on and C<%vrf_read> (VRF name to 1 for a complete
read, 0 for an incomplete one), the VRFs retired are those read whole, those
skipped (C<vrf_no_devicevrfs>), and, only when C<$vrf_list_complete> is 1, those the
run did not read at all; a VRF read short is never retired. With it on but no
C<%vrf_read> (an SSH or offline job, or a class without VRF support) nothing
is retired.

Returns the number of rows deactivated.

=cut

sub retire_unvouched_arps {
  my ($device, $now, $vrf_read, $vrf_list_complete) = @_;
  my $router = $device->ip;
  my $collecting = vrf_collection_enabled($device);

  if ($collecting and not $vrf_read) {
    debug sprintf ' [%s] arpnip - no VRF reads with store_vrfs on, retired nothing',
      $router;
    return 0;
  }

  my $where = "WHERE active AND router_last = ? AND time_last < $now";
  my ($retired, @vrfs) = (0);

  schema(vars->{'tenant'})->txn_do(sub {
    schema(vars->{'tenant'})->storage->dbh_do(sub {
      my (undef, $dbh) = @_;
      $dbh->do('SELECT pg_advisory_xact_lock(?, hashtext(host(?::inet)))',
        undef, $ARP_LOCK_CLASS, $router);

      if (not $collecting) {
        $retired = $dbh->do("UPDATE node_ip SET active = false $where AND vrf <> ''",
          undef, $router);
        return;
      }
      ($retired, @vrfs) = _retire_read_vrfs($dbh, $device, $where, $vrf_read, $vrf_list_complete);
    });
  });

  $retired = 0 + ($retired || 0);
  debug sprintf ' [%s] arpnip - retired %d ARP entries no longer reported, in %s',
    $router, $retired,
    ($collecting ? ('VRFs ['. (join ', ', map { qq{"$_"} } @vrfs) .']') : 'named VRFs');
  return $retired;
}

# idx_node_ip_vrf_named_active covers named-VRF rows only, so those
# statements repeat its predicate and the default table gets its own UPDATE
sub _retire_read_vrfs {
  my ($dbh, $device, $where, $vrf_read, $vrf_list_complete) = @_;
  my ($router, $retired) = ($device->ip, 0);

  my $stored = $dbh->selectcol_arrayref(
    "SELECT DISTINCT vrf FROM node_ip $where AND vrf <> ''", undef, $router);
  my $skipped = vrf_skip_test($device);
  my @named = grep { _vrf_unvouched($skipped, $_, $vrf_read, $vrf_list_complete) }
              sort @$stored;
  $retired += $dbh->do("UPDATE node_ip SET active = false $where"
    ." AND vrf <> '' AND vrf = ANY(?::text[])", undef, $router, \@named)
    if scalar @named;

  my $default = _vrf_unvouched($skipped, '', $vrf_read, $vrf_list_complete);
  $retired += $dbh->do("UPDATE node_ip SET active = false $where AND vrf = ''",
    undef, $router) if $default;

  return ($retired, ($default ? '' : ()), @named);
}

sub _vrf_unvouched {
  my ($skipped, $vrf, $vrf_read, $vrf_list_complete) = @_;
  return $vrf_read->{$vrf} if exists $vrf_read->{$vrf};
  return 1 if $skipped->($vrf);
  return ($vrf_list_complete ? 1 : 0);
}

1;
