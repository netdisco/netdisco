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
use Regexp::Common 'net';
use NetAddr::MAC ();
use Time::HiRes 'gettimeofday';

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
  vars->{'arps'} = [];
});

register_worker({ phase => 'store', title => 'store ARP cache' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  vars->{'arps'} = [ grep { check_mac(($_->{mac} || $_->{node}), $device) }
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
      $device->update({last_arpnip => \$now});
  }

  return Status->$status("Ended arpnip for $device");
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("arpnip failed: could not SNMP connect to $device");

  # cache v4 arp table
  push @{ vars->{'arps'} },
    get_arps_snmp($device, $snmp->at_paddr, $snmp->at_netaddr);

  # cache v6 neighbor cache
  push @{ vars->{'arps'} },
    get_arps_snmp($device, $snmp->ipv6_n2p_mac, $snmp->ipv6_n2p_addr);

  return Status->done("Gathered arp caches from $device");
});

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

  # should be both v4 and v6
  vars->{'arps'} = [ $cli->arpnip ];

  return Status->done("Gathered arp caches from $device");
});

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

      push @{ vars->{'arps'} }, $a_entry;
  }

  return Status->done("Received arp cache for $device");
});

true;
