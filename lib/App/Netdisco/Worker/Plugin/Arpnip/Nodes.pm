package App::Netdisco::Worker::Plugin::Arpnip::Nodes;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SSH ();
use App::Netdisco::Transport::SNMP ();

use App::Netdisco::Util::Node qw/check_mac store_arp/;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';

use NetAddr::IP::Lite ':lower';
use Time::HiRes 'gettimeofday';

register_worker({ phase => 'store' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # would be possible just to use now() on updated records, but by using this
  # same value for them all, we _can_ if we want add a job at the end to
  # select and do something with the updated set (no reason to yet, though)
  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';

  # update node_ip with ARP and Neighbor Cache entries

  store_arp(\%$_, $now) for @{ vars->{'v4arps'} };
  debug sprintf ' [%s] arpnip - processed %s ARP Cache entries',
    $device->ip, scalar @{ vars->{'v4arps'} };

  store_arp(\%$_, $now) for @{ vars->{'v6arps'} };
  debug sprintf ' [%s] arpnip - processed %s IPv6 Neighbor Cache entries',
    $device->ip, scalar @{ vars->{'v6arps'} };

  $device->update({last_arpnip => \$now});

  my $status = $job->best_status;
  return Status->$status("Ended arpnip for $device");
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("arpnip failed: could not SNMP connect to $device");

  # cache v4 arp table
  push @{ vars->{'v4arps'} },
    @{ get_arps_snmp($device, $snmp->at_paddr, $snmp->at_netaddr) };

  # cache v6 neighbor cache
  push @{ vars->{'v6arps'} },
    @{get_arps_snmp($device, $snmp->ipv6_n2p_mac, $snmp->ipv6_n2p_addr) };

  return Status->done("Gathered arp caches from $device");
});

# get an arp table (v4 or v6)
sub get_arps_snmp {
  my ($device, $paddr, $netaddr) = @_;
  my @arps = ();

  while (my ($arp, $node) = each %$paddr) {
      my $ip = $netaddr->{$arp};
      next unless defined $ip;
      next unless check_mac($node, $device);
      push @arps, {
        node => $node,
        ip   => $ip,
        dns  => undef,
      };
  }

  debug sprintf ' resolving %d ARP entries with max %d outstanding requests',
    scalar @arps, $ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'};
  my $resolved_ips = hostnames_resolve_async(\@arps);

  return $resolved_ips;
}

register_worker({ phase => 'main', driver => 'cli' }, sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    my $cli = App::Netdisco::Transport::SSH->session_for($device)
      or return Status->defer("arpnip failed: could not SSH connect to $device");

    # should be both v4 and v6
    my @arps = @{ get_arps_cli($device, [$cli->arpnip]) };

    # cache v4 arp table
    push @{ vars->{'v4arps'} },
      grep { NetAddr::IP::Lite->new($_->{ip})->bits ==  32 } @arps;

    # cache v6 neighbor cache
    push @{ vars->{'v6arps'} },
      grep { NetAddr::IP::Lite->new($_->{ip})->bits == 128 } @arps;

    return Status->done("Gathered arp caches from $device");
});

sub get_arps_cli {
  my ($device, $entries) = @_;
  my @arps = ();
  $entries ||= [];

  foreach my $entry (@$entries) {
    next unless check_mac($entry->{mac}, $device);
    push @arps, {
        node => $entry->{mac},
        ip   => $entry->{ip},
        dns  => $entry->{dns},
    };
  }

  debug sprintf ' resolving %d ARP entries with max %d outstanding requests',
    scalar @arps, $ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'};
  my $resolved_ips = hostnames_resolve_async(\@arps);

  return $resolved_ips;
}

true;
