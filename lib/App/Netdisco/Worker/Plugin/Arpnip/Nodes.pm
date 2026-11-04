package App::Netdisco::Worker::Plugin::Arpnip::Nodes;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SSH ();
use App::Netdisco::Transport::SNMP ();

use App::Netdisco::Util::Node qw/check_mac memoize_arp store_arp retire_unvouched_arps/;
use App::Netdisco::Util::VRF
  qw/vrf_collection_enabled vrf_skipped netdisco_vrf vrf_instances_for each_vrf_instance/;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';

use NetAddr::IP::Lite ':lower';
use Regexp::Common 'net';
use NetAddr::MAC ();
use Time::HiRes 'gettimeofday';
use Try::Tiny;

register_worker({ phase => 'early',
  title => 'prepare common data' }, sub {

  my ($job, $workerconf) = @_;
  my $device = $job->device;

  vars->{'timestamp'} = ($job->is_offline and $job->entered)
    ? (schema('netdisco')->storage->dbh->quote($job->entered) .'::timestamp')
    : 'to_timestamp('. (join '.', gettimeofday) .')::timestamp';

  # initialise the cache
  vars->{'arps'} = {};
  # netdisco-do runs every job in one process, so no job sees another's VRF reads
  delete @{ vars() }{qw/vrf_read vrf_read_families vrf_list_complete/};
});

register_worker({ phase => 'store', title => 'store ARP cache' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # convert cache to a list, now that we've gathererd all of them
  # it just makes the rest of the "store" code easier
  vars->{'arps'} = [ values %{ vars->{'arps'} } ];

  drop_flattened_twins($device) if vrf_collection_enabled($device);

  vars->{'arps'} = [ grep { check_mac(($_->{node} || $_->{mac}), $device) }
                          @{ vars->{'arps'} } ];

  debug sprintf ' resolving %d ARP entries with max %d outstanding requests',
    scalar @{ vars->{'arps'} }, $ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'};
  vars->{'arps'} = hostnames_resolve_async( vars->{'arps'} );

  my ($v4, $v6) = (0, 0);
  foreach my $a_entry (@{ vars->{'arps'} }) {
    my $a_ip = NetAddr::IP::Lite->new($a_entry->{ip});

    if ($a_ip) {
      ++$v4 if $a_ip->bits == 32;;
      ++$v6 if $a_ip->bits == 128;;
    }
  }

  my $now = vars->{'timestamp'};
  store_arp(\%$_, $now, $device->ip) for @{ vars->{'arps'} };

  debug sprintf ' [%s] arpnip - processed %s ARP Cache entries',
    $device->ip, $v4;
  debug sprintf ' [%s] arpnip - processed %s IPv6 Neighbor Cache entries',
    $device->ip, $v6;

  my $status = $job->best_status;
  if (Status->$status->level == Status->done->level) {
      # the entries are stored, so a failed retire leaves stale rows active
      # until the next arpnip retries, rather than failing this job
      try { retire_unvouched_arps($device, $now, vars->{'vrf_read'}, vars->{'vrf_list_complete'}) }
      catch { warning sprintf ' [%s] arpnip - retiring unreported entries failed, the next arpnip retries: %s',
        $device->ip, $_ };
      $device->update({last_arpnip => \$now});
  }

  return Status->$status("Ended arpnip for $device");
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("arpnip failed: could not SNMP connect to $device");

  my $instances = vrf_instances_for($device, $snmp);
  if ($instances) {
    gather_arps_per_vrf($device, $snmp, $instances);
    return Status->done("Gathered arp caches from $device");
  }

  # cache v4 arp table
  map { vars->{'arps'}->{ memoize_arp($_) } = $_ }
      get_arps_snmp($device, $snmp->at_paddr, $snmp->at_netaddr);

  # cache v6 neighbor cache
  map { vars->{'arps'}->{ memoize_arp($_) } = $_ }
      get_arps_snmp($device, $snmp->ipv6_n2p_mac, $snmp->ipv6_n2p_addr);

  return Status->done("Gathered arp caches from $device");
});

# a flattening CLI collector reports a host with no VRF that a VRF-aware driver
# reported under its VRF in the same job; keep only the named one. Accepted
# edge: a host really in both '' and a named VRF keeps only the named row.
sub drop_flattened_twins {
  my ($device) = @_;
  my $key_of = sub {
    my $entry = shift;
    my $mac = NetAddr::MAC->new(mac => ($entry->{node} || $entry->{mac} || ''));
    my $ip = NetAddr::IP::Lite->new($entry->{ip} || '');
    return ($mac and $ip) ? join(chr(28), $mac->as_ieee, $ip->addr) : undef;
  };

  my %named = map { my $key = $key_of->($_); defined $key ? ($key => 1) : () }
              grep { length($_->{vrf} // '') } @{ vars->{'arps'} };
  return unless %named;

  my @kept = grep { my $key = (length($_->{vrf} // '') ? undef : $key_of->($_));
                    not (defined $key and $named{$key}) } @{ vars->{'arps'} };
  my $dropped = scalar(@{ vars->{'arps'} }) - scalar(@kept);
  vars->{'arps'} = \@kept;

  debug sprintf ' [%s] arpnip - dropped %d flattened ARP entries also reported under a VRF',
    $device->ip, $dropped if $dropped;
}

# store_vrfs path: each VRF's ARP and neighbor entries are read in its own
# context, and vrf_read says which VRFs were read whole
sub gather_arps_per_vrf {
  my ($device, $snmp, $instances) = @_;
  # read before any switch, as update() clears SNMP::Info's cache
  my $list_complete = $snmp->vrf_instances_complete;

  my $reads = each_vrf_instance($device, $snmp, $instances,
    sub { return $snmp->vrf_neighbors($_[0]) }, log_as => 'arpnip');
  # vrf_neighbors reads both the ARP and the IPv6 neighbor rows
  merge_vrf_reads({ map { ($_ => $reads->{$_}->{complete}) } keys %$reads }, $list_complete, [4, 6]);

  foreach my $vrf (sort keys %$reads) {
    my $neighbors = $reads->{$vrf}->{data} || {};
    foreach my $key (sort keys %$neighbors) {
      my $arp = { mac => $neighbors->{$key}->{mac}, ip => $neighbors->{$key}->{ip},
                  dns => undef, vrf => $vrf };
      vars->{'arps'}->{ memoize_arp($arp) } = $arp;
    }
  }
}

# get an arp table (v4 or v6)
sub get_arps_snmp {
  my ($device, $paddr, $netaddr) = @_;
  my @arps = ();

  while (my ($arp, $node) = each %$paddr) {
      my $ip = $netaddr->{$arp} or next;
      push @arps, {
        mac => $node,
        ip  => $ip,
        dns => undef,
      };
  }

  return @arps;
}

register_worker({ phase => 'main', driver => 'cli' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $cli = App::Netdisco::Transport::SSH->session_for($device)
    or return Status->defer("arpnip failed: could not SSH connect to $device");

  if (vrf_collection_enabled($device)) {
    return gather_arps_by_vrf_cli($device, $cli)
      if $cli->platform->can('arpnip_by_vrf');
    debug sprintf ' [%s] arpnip - %s collector flattens VRFs and contributes no VRF reads',
      $device->ip, ref $cli->platform;
  }

  # should be both v4 and v6
  map { vars->{'arps'}->{ memoize_arp($_) } = $_ }
      $cli->arpnip;

  return Status->done("Gathered arp caches from $device");
});

# a platform with arpnip_by_vrf returns { entries, vrf_read, vrf_list_complete,
# families } with each entry's vrf named as netdisco stores it; families lists
# the address families its vrf_read covers, [4] or [4, 6], and absent means [4, 6]
sub gather_arps_by_vrf_cli {
  my ($device, $cli) = @_;
  my $error = 'returned no ARP data';
  my $result = try { $cli->arpnip_by_vrf } catch { ($error = "failed: $_") =~ s{\s+\z}{}; undef };
  return Status->defer("arpnip failed: CLI session to $device $error")
    unless ref {} eq ref $result;

  my %vrf_read = ();
  my $reads = $result->{vrf_read} || {};
  foreach my $vrf (keys %$reads) {
    my $name = netdisco_vrf($vrf);
    # default and '' name one table, so it is whole only if both reads were
    $vrf_read{$name} = (exists $vrf_read{$name} ? ($vrf_read{$name} && $reads->{$vrf}) : $reads->{$vrf});
  }
  # a platform that read no VRF cannot vouch that its list is whole
  my $list_complete = (scalar keys %vrf_read ? $result->{vrf_list_complete} : 0);

  foreach my $entry (@{ $result->{entries} || [] }) {
    my $vrf = netdisco_vrf($entry->{vrf}) // '';
    next if vrf_skipped($device, $vrf);
    # entries from a VRF the platform did not report reading prove no read
    $vrf_read{$vrf} = 0 unless exists $vrf_read{$vrf};
    my $arp = { %$entry, vrf => $vrf };
    vars->{'arps'}->{ memoize_arp($arp) } = $arp;
  }

  delete @vrf_read{ grep { vrf_skipped($device, $_) } keys %vrf_read };
  merge_vrf_reads(\%vrf_read, $list_complete, $result->{families});
  return Status->done("Gathered arp caches from $device");
}

# SNMP and CLI may both read a VRF in one job. Per address family, a VRF is
# whole only if every source that read that family read it whole; vrf_read is
# 1 only when both families were read whole by some source. The list is whole
# only if every source's list was. A source that read no VRF leaves vrf_read
# absent, so nothing retires on its word.
sub merge_vrf_reads {
  my ($reads, $list_complete, $families) = @_;
  my @families = (_well_formed_families($families) ? @$families : (4, 6));
  my $by_family = (vars->{'vrf_read_families'} ||= {});

  foreach my $vrf (keys %$reads) {
    my $whole = ($reads->{$vrf} ? 1 : 0);
    foreach my $family (@families) {
      my $seen = $by_family->{$vrf}->{$family};
      $by_family->{$vrf}->{$family} = (defined $seen ? ($seen && $whole) : $whole);
    }
    vars->{'vrf_read'}->{$vrf} = ((2 == grep { $by_family->{$vrf}->{$_} } 4, 6) ? 1 : 0);
  }
  my $list = ($list_complete ? 1 : 0);
  vars->{'vrf_list_complete'} = (exists vars->{'vrf_list_complete'}
    ? (vars->{'vrf_list_complete'} && $list) : $list);
}

# anything but a non-empty list of 4 and 6 reads as absent, never as no family
sub _well_formed_families {
  my $families = shift;
  return 0 unless ref [] eq ref $families and scalar @$families;
  return not scalar grep { not defined $_ or $_ !~ m/^[46]\z/ } @$families;
}

register_worker({ phase => 'main', driver => 'direct' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  return Status->info('skip: arp table data supplied by other source')
    unless $job->is_offline;

  # load cache from file or copy from job param
  my $data = $job->extra;
  my @arps = (length $data ? @{ from_json($data) } : ());

  return $job->cancel('data provided but 0 arp entries found')
    unless scalar @arps;

  debug sprintf ' [%s] arpnip - %s arp table entries provided',
    $device->ip, scalar @arps;

  # sanity check
  foreach my $a_entry (@arps) {
      my $ip  = NetAddr::IP::Lite->new($a_entry->{'ip'} || '');
      my $mac = NetAddr::MAC->new(mac => ($a_entry->{'mac'} || ''));

      next unless $ip and $mac;
      next if (($ip->addr eq '0.0.0.0') or ($ip !~ m{^(?:$RE{net}{IPv4}|$RE{net}{IPv6})(?:/\d+)?$}i));
      next if (($mac->as_ieee eq '00:00:00:00:00:00') or ($mac->as_ieee !~ m{^$RE{net}{MAC}$}i));

      vars->{'arps'}->{ memoize_arp($a_entry) } = $a_entry;
  }

  return Status->done("Received arp cache for $device");
});

true;
