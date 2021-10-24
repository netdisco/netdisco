package App::Netdisco::Worker::Plugin::Arpnip::Subnets;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'check_acl_no';
use Dancer::Plugin::DBIC 'schema';
use NetAddr::IP::Lite ':lower';
use Time::HiRes 'gettimeofday';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("arpnip failed: could not SNMP connect to $device");

  # get directly connected networks
  my @subnets = gather_subnets($device);
  # TODO: IPv6 subnets

  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';
  store_subnet($_, $now) for @subnets;

  return Status->info(sprintf ' [%s] arpnip - processed %s Subnet entries',
    $device->ip, scalar @subnets);
});

# gathers device subnets
sub gather_subnets {
  my $device = shift;
  my @subnets = ();

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return (); # already checked!

  my $ip_netmask = $snmp->ip_netmask;
  foreach my $entry (keys %$ip_netmask) {
      my $ip = NetAddr::IP::Lite->new($entry) or next;
      my $addr = $ip->addr;

      next if $addr eq '0.0.0.0';
      next if check_acl_no($ip, 'group:__LOCAL_ADDRESSES__');
      next if setting('ignore_private_nets') and $ip->is_rfc1918;

      my $netmask = $ip_netmask->{$addr} || $ip->bits();
      next if $netmask eq '255.255.255.255' or $netmask eq '0.0.0.0';

      my $cidr = NetAddr::IP::Lite->new($addr, $netmask)->network->cidr;

      debug sprintf ' [%s] arpnip - found subnet %s', $device->ip, $cidr;
      push @subnets, $cidr;
  }

  return @subnets;
}

# update subnets with new networks
sub store_subnet {
  my ($subnet, $now) = @_;

  schema('netdisco')->txn_do(sub {
    schema('netdisco')->resultset('Subnet')->update_or_create(
    {
      net => $subnet,
      last_discover => \$now,
    },
    { for => 'update' });
  });
}

true;
