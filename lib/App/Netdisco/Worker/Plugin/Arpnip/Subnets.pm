package App::Netdisco::Worker::Plugin::Arpnip::Subnets;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'acl_matches';
use Dancer::Plugin::DBIC 'schema';
use NetAddr::IP::Lite ':lower';
use Time::HiRes 'gettimeofday';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("arpnip (snmp) failed: could not SNMP connect to $device");

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

register_worker({ phase => 'main', driver => 'cli' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $cli = App::Netdisco::Transport::SSH->session_for($device)
    or return Status->defer("arpnip (cli) failed: could not SSH connect to $device");

  my @subnets = grep { defined and length } $cli->subnets;

  debug sprintf ' [%s] arpnip (cli) - found subnet %s', $device->ip, $_ for @subnets;
  store_subnet($_) for @subnets;

  return Status->info(sprintf ' [%s] arpnip (cli) - processed %s Subnet entries',
    $device->ip, scalar @subnets);
});

register_worker({ phase => 'store', title => 'store subnets' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # my $subs = vars->{'subnets'};
  # use DDP; p $subs;

  my $now = vars->{'timestamp'}
    || ('to_timestamp('. (join '.', gettimeofday) .')::timestamp');

  # update subnets with new networks
  foreach my $subnet (keys %{ vars->{'subnets'} }) {
      schema('netdisco')->txn_do(sub {
        schema('netdisco')->resultset('Subnet')->update_or_create(
        {
          net => $subnet,
          last_discover => \$now,
        },
        { for => 'update' });
      });
  }

  debug sprintf ' [%s] arpnip - processed %s subnets',
    $device->ip, scalar keys %{ vars->{'subnets'} };

  return Status->info("Stored subnets for $device");
});

sub store_subnet {
  my ($subnet) = @_;
  return unless $subnet;
  vars->{'subnets'}->{$subnet} += 1;
}

true;
