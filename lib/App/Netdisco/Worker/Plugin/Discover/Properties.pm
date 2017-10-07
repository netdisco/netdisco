package App::Netdisco::Worker::Plugin::Discover::Properties;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'check_acl_no';
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';
use App::Netdisco::Util::DNS 'hostname_from_ip';
use Dancer::Plugin::DBIC 'schema';
use NetAddr::IP::Lite ':lower';
use Encode;

register_worker({ stage => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $ip_index   = $snmp->ip_index;
  my $interfaces = $snmp->interfaces;
  my $ip_netmask = $snmp->ip_netmask;

  # build device aliases suitable for DBIC
  my @aliases;
  foreach my $entry (keys %$ip_index) {
      my $ip = NetAddr::IP::Lite->new($entry)
        or next;
      my $addr = $ip->addr;

      next if $addr eq '0.0.0.0';
      next if check_acl_no($ip, 'group:__LOCAL_ADDRESSES__');
      next if setting('ignore_private_nets') and $ip->is_rfc1918;

      my $iid = $ip_index->{$addr};
      my $port = $interfaces->{$iid};
      my $subnet = $ip_netmask->{$addr}
        ? NetAddr::IP::Lite->new($addr, $ip_netmask->{$addr})->network->cidr
        : undef;

      debug sprintf ' [%s] device - aliased as %s', $device->ip, $addr;
      push @aliases, {
          alias => $addr,
          port => $port,
          subnet => $subnet,
          dns => undef,
      };
  }

  debug sprintf ' resolving %d aliases with max %d outstanding requests',
      scalar @aliases, $ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'};
  my $resolved_aliases = hostnames_resolve_async(\@aliases);

  # fake one aliases entry for devices not providing ip_index
  push @$resolved_aliases, { alias => $device->ip, dns => $device->dns }
    if 0 == scalar @aliases;

  # VTP Management Domain -- assume only one.
  my $vtpdomains = $snmp->vtp_d_name;
  my $vtpdomain;
  if (defined $vtpdomains and scalar values %$vtpdomains) {
      $device->set_column( vtp_domain => (values %$vtpdomains)[-1] );
  }

  my $hostname = hostname_from_ip($device->ip);
  $device->set_column( dns => $hostname ) if $hostname;

  my @properties = qw/
    snmp_ver
    description uptime name
    layers ports mac
    ps1_type ps2_type ps1_status ps2_status
    fan slots
    vendor os os_ver
  /;

  foreach my $property (@properties) {
      $device->set_column( $property => $snmp->$property );
  }

  $device->set_column( model  => Encode::decode('UTF-8', $snmp->model)  );
  $device->set_column( serial => Encode::decode('UTF-8', $snmp->serial) );
  $device->set_column( contact => Encode::decode('UTF-8', $snmp->contact) );
  $device->set_column( location => Encode::decode('UTF-8', $snmp->location) );


  $device->set_column( snmp_class => $snmp->class );
  $device->set_column( last_discover => \'now()' );

  schema('netdisco')->txn_do(sub {
    my $gone = $device->device_ips->delete;
    debug sprintf ' [%s] device - removed %d aliases',
      $device->ip, $gone;
    $device->update_or_insert(undef, {for => 'update'});
    $device->device_ips->populate($resolved_aliases);
    debug sprintf ' [%s] device - added %d new aliases',
      $device->ip, scalar @aliases;
  });

  return Status->done("Ended discover for $device");
});

true;
