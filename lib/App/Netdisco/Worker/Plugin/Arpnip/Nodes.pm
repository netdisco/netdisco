package App::Netdisco::Worker::Plugin::Arpnip::Nodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';
use App::Netdisco::Transport::CLI ();
use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Node qw/check_mac store_arp/;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';
use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';
use Module::Load ();
use Net::OpenSSH;
use Try::Tiny;

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("arpnip snmp failed: could not SNMP connect to $device");

  # get v4 arp table
  my $v4 = get_arps_snmp($device, $snmp->at_paddr, $snmp->at_netaddr);
  # get v6 neighbor cache
  my $v6 = get_arps_snmp($device, $snmp->ipv6_n2p_mac, $snmp->ipv6_n2p_addr);

  # would be possible just to use now() on updated records, but by using this
  # same value for them all, we _can_ if we want add a job at the end to
  # select and do something with the updated set (no reason to yet, though)
  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';

  # update node_ip with ARP and Neighbor Cache entries
  store_arp(\%$_, $now) for @$v4;
  debug sprintf ' [%s] arpnip snmp - processed %s ARP Cache entries',
    $device->ip, scalar @$v4;

  store_arp(\%$_, $now) for @$v6;
  debug sprintf ' [%s] arpnip snmp - processed %s IPv6 Neighbor Cache entries',
    $device->ip, scalar @$v6;

  $device->update({last_arpnip => \$now});
  return Status->done("Ended arpnip snmp for $device");
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

    if (get_arps_cli($device)){
      my $now = 'to_timestamp('. (join '.', gettimeofday) .')';
      $device->update({last_arpnip => \$now});
      my $endmsg = "Ended arpnip cli for $device"; 
      info sprintf " [%s] arpnip cli - $endmsg", $device->ip;
      return Status->done($endmsg);
    }else{
      Status->defer("arpnip cli failed");
    }

});

sub get_arps_cli {
  my ($device) = @_;

  my ($ssh, $selected_auth) = App::Netdisco::Transport::CLI->session_for($device->ip, "sshcollector");

  unless ($ssh){
    my $msg = "could not connect to $device with SSH, deferring job"; 
    warning sprintf " [%s] arpnip cli - %s", $device->ip, $msg;
    return undef;
  }

  my $class = "App::Netdisco::SSHCollector::Platform::".$selected_auth->{platform};
  debug sprintf " [%s] arpnip cli - delegating to platform module %s", $device->ip, $class;

  my $load_failed = 0;
  try {
    Module::Load::load $class;
  } catch {
    warning sprintf " [%s] arpnip cli - failed to load %s: %s", $device->ip, $class, substr($_, 0, 50)."...";
    $load_failed = 1;
  };
  return undef if $load_failed;

  my $platform_class = $class->new();
  my $arpentries = [ $platform_class->arpnip($device->ip, $ssh, $selected_auth) ];

  if (not scalar @$arpentries) {
    warning sprintf " [%s] WARNING: no entries received from device", $device->ip;
  }

  hostnames_resolve_async($arpentries);

  foreach my $arpentry ( @$arpentries ) {

    # skip broadcast/vrrp/hsrp and other weirdos
    next unless check_mac( $arpentry->{mac} );

    debug sprintf ' [%s] arpnip cli - stored entry: %s / %s / %s',
    $device->ip, $arpentry->{mac}, $arpentry->{ip}, 
    $arpentry->{dns} if defined $arpentry->{dns};
    store_arp({
        node => $arpentry->{mac},
        ip => $arpentry->{ip},
        dns => $arpentry->{dns},
      });
  }

  return 1;
}

true;
