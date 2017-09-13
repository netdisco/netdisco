package App::Netdisco::Worker::Plugin::Arpnip::Nodes;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Node 'check_mac';
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';
use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';
use NetAddr::MAC ();

register_worker({ stage => 'check', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("arpnip failed: could not SNMP connect to $device");

  return Status->defer("Skipped arpnip for device $device without layer 3 capability")
    unless $snmp->has_layer(3);

  # get v4 arp table
  my $v4 = get_arps($device, $snmp->at_paddr, $snmp->at_netaddr);
  # get v6 neighbor cache
  my $v6 = get_arps($device, $snmp->ipv6_n2p_mac, $snmp->ipv6_n2p_addr);

  # would be possible just to use now() on updated records, but by using this
  # same value for them all, we _can_ if we want add a job at the end to
  # select and do something with the updated set (no reason to yet, though)
  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';

  # update node_ip with ARP and Neighbor Cache entries
  store_arp(\%$_, $now) for @$v4;
  debug sprintf ' [%s] arpnip - processed %s ARP Cache entries',
    $device->ip, scalar @$v4;

  store_arp(\%$_, $now) for @$v6;
  debug sprintf ' [%s] arpnip - processed %s IPv6 Neighbor Cache entries',
    $device->ip, scalar @$v6;

  $device->update({last_arpnip => \$now});
  return Status->done("Ended arpnip for $device");
});

# get an arp table (v4 or v6)
sub get_arps {
  my ($device, $paddr, $netaddr) = @_;
  my @arps = ();

  while (my ($arp, $node) = each %$paddr) {
      my $ip = $netaddr->{$arp};
      next unless defined $ip;
      next unless check_mac($device, $node);
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

=head2 store_arp( \%host, $now? )

Stores a new entry to the C<node_ip> table with the given MAC, IP (v4 or v6)
and DNS host name. Host details are provided in a Hash ref:

 {
    ip   => '192.0.2.1',
    node => '00:11:22:33:44:55',
    dns  => 'myhost.example.com',
 }

The C<dns> entry is optional. The update will mark old entries for this IP as
no longer C<active>.

Optionally a literal string can be passed in the second argument for the
C<time_last> timestamp, otherwise the current timestamp (C<now()>) is used.

=cut

sub store_arp {
  my ($hash_ref, $now) = @_;
  $now ||= 'now()';
  my $ip   = $hash_ref->{'ip'};
  my $mac  = NetAddr::MAC->new($hash_ref->{'node'});
  my $name = $hash_ref->{'dns'};

  return if !defined $mac or $mac->errstr;

  schema('netdisco')->txn_do(sub {
    my $current = schema('netdisco')->resultset('NodeIp')
      ->search(
        { ip => $ip, -bool => 'active'},
        { columns => [qw/mac ip/] })->update({active => \'false'});

    schema('netdisco')->resultset('NodeIp')
      ->update_or_create(
      {
        mac => $mac->as_ieee,
        ip => $ip,
        dns => $name,
        active => \'true',
        time_last => \$now,
      },
      {
        key => 'primary',
        for => 'update',
      });
  });
}

true;
