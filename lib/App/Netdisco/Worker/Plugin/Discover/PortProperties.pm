package App::Netdisco::Worker::Plugin::Discover::PortProperties;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $interfaces = $snmp->interfaces || {};
  my $err_cause = $snmp->i_err_disable_cause || {};

  my %properties = ();
  foreach my $idx (keys %$err_cause) {
    my $port = $interfaces->{$idx};
    next unless $port;

    $properties{ $port }->{error_disable_cause} = $err_cause->{$idx};
  }

  my $lldp_if  = $snmp->lldp_if  || {};
  my $lldp_cap = $snmp->lldp_cap || {};
  my $rem_media_cap = $snmp->lldp_media_cap || {};
  my $rem_vendor = $snmp->lldp_rem_vendor || {};
  my $rem_model  = $snmp->lldp_rem_model  || {};
  my $rem_os_ver = $snmp->lldp_rem_sw_rev || {};
  my $rem_serial = $snmp->lldp_rem_serial || {};

  foreach my $idx (keys %$lldp_if) {
    my $port = $interfaces->{ $lldp_if->{$idx} };
    next unless $port;

    $properties{ $port }->{remote_is_wap} = 'true'
      if scalar grep {defined && m/^wlanAccessPoint$/} @{ $lldp_cap->{$idx} };
    $properties{ $port }->{remote_is_phone} = 'true'
      if scalar grep {defined && m/^telephone$/} @{ $lldp_cap->{$idx} };

    next unless scalar grep {defined && m/^inventory$/} @{ $rem_media_cap->{$idx} };

    $properties{ $port }->{remote_vendor} = $rem_vendor->{ $idx };
    $properties{ $port }->{remote_model}  = $rem_model->{ $idx };
    $properties{ $port }->{remote_os_ver} = $rem_os_ver->{ $idx };
    $properties{ $port }->{remote_serial} = $rem_serial->{ $idx };
  }

  return Status->info(" [$device] no port properties to record")
    unless scalar keys %properties;

  schema('netdisco')->txn_do(sub {
    my $gone = $device->properties_ports->delete;
    debug sprintf ' [%s] props - removed %d ports with properties',
      $device->ip, $gone;
    $device->properties_ports->populate(
      [map {{ port => $_, %{ $properties{$_} } }} keys %properties] );

    return Status->info(sprintf ' [%s] props - added %d new port properties',
      $device->ip, scalar keys %properties);
  });
});

true;
