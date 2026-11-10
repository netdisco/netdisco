package App::Netdisco::Worker::Plugin::Arpnip::Subnets;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Transport::SSH ();
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::Util::VRF qw/
  vrf_collection_enabled vrf_skip_test netdisco_vrf vrf_instances_for each_vrf_instance/;
use Dancer::Plugin::DBIC 'schema';
use NetAddr::IP::Lite ':lower';
use Time::HiRes 'gettimeofday';
use List::Util 'sum0';
use Try::Tiny;

register_worker({ phase => 'early', title => 'prepare subnets' }, sub {
  # netdisco-do runs every job in one process, so no job sees another's subnets
  delete vars->{'subnets'};
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("arpnip (snmp) failed: could not SNMP connect to $device");

  my $instances = vrf_instances_for($device, $snmp);
  return store_vrf_subnets($device, $snmp, $instances) if $instances;

  # TODO: IPv6 subnets
  my @subnets = ();

  my $ip_netmask = $snmp->ip_netmask;
  foreach my $entry (keys %$ip_netmask) {
      my $ip = NetAddr::IP::Lite->new($entry) or next;
      my $addr = $ip->addr;

      next if $addr eq '0.0.0.0';
      next if acl_matches($ip, 'group:__LOOPBACK_ADDRESSES__');
      next if setting('ignore_private_nets') and $ip->is_rfc1918;

      my $netmask = $ip_netmask->{$addr} || $ip->bits();
      next if $netmask eq '255.255.255.255' or $netmask eq '0.0.0.0';

      my $cidr = NetAddr::IP::Lite->new($addr, $netmask)->network->cidr;
      push @subnets, $cidr;
  }

  debug sprintf ' [%s] arpnip (snmp) - found subnet %s', $device->ip, $_ for @subnets;
  store_subnet($_) for @subnets;

  return Status->info(sprintf ' [%s] arpnip (snmp) - processed %s Subnet entries',
    $device->ip, scalar @subnets);
});

# store_vrfs path: each VRF's subnets are read in its own context; a VRF whose
# read came back short stores none, so its stored rows are left alone
sub store_vrf_subnets {
  my ($device, $snmp, $instances) = @_;

  my $reads = each_vrf_instance($device, $snmp, $instances,
    sub { return $snmp->vrf_subnets($_[0]) }, log_as => 'arpnip');

  my $count = 0;
  foreach my $vrf (sort keys %$reads) {
    next unless $reads->{$vrf}->{complete};
    my $found = $reads->{$vrf}->{data} || {};
    foreach my $key (sort keys %$found) {
      my $cidr = vrf_subnet_cidr($found->{$key}) or next;
      debug sprintf ' [%s] arpnip (snmp) - found subnet %s in vrf "%s"', $device->ip, $cidr, $vrf;
      store_subnet($cidr, $vrf);
      ++$count;
    }
  }

  return Status->info(sprintf ' [%s] arpnip (snmp) - processed %s Subnet entries',
    $device->ip, $count);
}

# the network of a vrf_subnets entry in CIDR form, or undef for one that is
# not stored: unspecified, host, loopback, link-local and (when configured) private
sub vrf_subnet_cidr {
  my ($entry) = @_;
  my ($prefix, $len) = @$entry{qw/prefix len/};
  return undef unless defined $prefix and defined $len;

  my $ip = NetAddr::IP::Lite->new($prefix) or return undef;
  my $is_v6 = $ip->version == 6;
  return undef if $len == 0 or $len == ($is_v6 ? 128 : 32);
  return undef if $ip->addr eq '0.0.0.0' or acl_matches($ip, 'group:__LOOPBACK_ADDRESSES__');

  if ($is_v6) {
    return undef if NetAddr::IP::Lite->new('fe80::/10')->contains($ip);
    return undef if setting('ignore_private_nets') and NetAddr::IP::Lite->new('fc00::/7')->contains($ip);
  }
  else {
    return undef if setting('ignore_private_nets') and $ip->is_rfc1918;
  }

  my $network = NetAddr::IP::Lite->new($ip->addr, $len) or return undef;
  return $network->network->cidr;
}

register_worker({ phase => 'main', driver => 'cli' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $cli = App::Netdisco::Transport::SSH->session_for($device)
    or return Status->defer("arpnip (cli) failed: could not SSH connect to $device");

  return store_cli_vrf_subnets($device, $cli)
    if vrf_collection_enabled($device) and $cli->platform->can('subnets_by_vrf');

  my @subnets = grep { defined and length } $cli->subnets;

  debug sprintf ' [%s] arpnip (cli) - found subnet %s', $device->ip, $_ for @subnets;
  store_subnet($_) for @subnets;

  return Status->info(sprintf ' [%s] arpnip (cli) - processed %s Subnet entries',
    $device->ip, scalar @subnets);
});

# a platform with subnets_by_vrf returns { VRF => [ { prefix, len } ] } with the
# device's own VRF names, or undef when it read nothing. Nothing read stores
# nothing and is not a defer: subnets never retire, and the ARP worker defers.
# A platform subclass that overrides subnets must also override subnets_by_vrf,
# or with store_vrfs on the inherited subnets_by_vrf runs instead of its subnets.
sub store_cli_vrf_subnets {
  my ($device, $cli) = @_;
  my $error = 'returned no subnet data';
  my $found = try { $cli->subnets_by_vrf } catch { ($error = "failed: $_") =~ s{\s+\z}{}; undef };
  unless (ref {} eq ref $found) {
    debug sprintf ' [%s] arpnip (cli) - subnets_by_vrf %s, so no subnets are stored', $device->ip, $error;
    return Status->info(sprintf ' [%s] arpnip (cli) - processed 0 Subnet entries', $device->ip);
  }

  my %seen;
  my $skipped = vrf_skip_test($device);
  foreach my $device_vrf (sort keys %$found) {
    my $vrf = netdisco_vrf($device_vrf);
    next if $skipped->($vrf);
    unless (ref [] eq ref $found->{$device_vrf}) {
      debug sprintf ' [%s] arpnip (cli) - subnets for vrf "%s" are not a list, skipped', $device->ip, $vrf;
      next;
    }
    foreach my $entry (@{ $found->{$device_vrf} }) {
      unless (ref {} eq ref $entry) {
        debug sprintf ' [%s] arpnip (cli) - subnet entry in vrf "%s" is not a hash, skipped', $device->ip, $vrf;
        next;
      }
      my $cidr = vrf_subnet_cidr($entry) or next;
      debug sprintf ' [%s] arpnip (cli) - found subnet %s in vrf "%s"', $device->ip, $cidr, $vrf;
      store_subnet($cidr, $vrf);
      $seen{$vrf}{$cidr} = 1;
    }
  }

  my $count = sum0(map { scalar keys %$_ } values %seen);
  return Status->info(sprintf ' [%s] arpnip (cli) - processed %s Subnet entries',
    $device->ip, $count);
}

register_worker({ phase => 'store', title => 'store subnets' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # my $subs = vars->{'subnets'};
  # use DDP; p $subs;

  my $now = vars->{'timestamp'}
    || (sprintf 'to_timestamp(%d.%06d)::timestamp', gettimeofday);

  # update subnets with new networks
  my $stored = 0;
  foreach my $vrf (sort keys %{ vars->{'subnets'} || {} }) {
    foreach my $cidr (keys %{ vars->{'subnets'}->{$vrf} }) {
      schema('netdisco')->resultset('Subnet')->upsert_subnet($cidr, $now, $vrf, $device->ip);
      ++$stored;
    }
  }

  debug sprintf ' [%s] arpnip - processed %s subnets', $device->ip, $stored;

  return Status->info("Stored subnets for $device");
});

sub store_subnet {
  my ($subnet, $vrf) = @_;
  return unless $subnet;
  vars->{'subnets'}->{ $vrf // '' }->{$subnet} = 1;
}

true;
