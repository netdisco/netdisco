package App::Netdisco::Worker::Plugin::Discover::PortProperties;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use Dancer::Plugin::DBIC 'schema';

use Encode;
use App::Netdisco::Util::Device 'match_to_setting';

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  return unless $device->in_storage;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("discover failed: could not SNMP connect to $device");

  my $interfaces = $snmp->interfaces || {};
  my %properties = ();

  # cache the device ports to save hitting the database for many single rows
  my $device_ports = vars->{'device_ports'}
    || { map {($_->port => $_)} $device->ports->all };

  my $raw_speed = $snmp->i_speed_raw || {};

  foreach my $idx (keys %$raw_speed) {
    my $port = $interfaces->{$idx} or next;
    if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] properties/speed - local port %s already skipped, ignoring',
          $device->ip, $port;
        next;
    }

    $properties{ $port }->{raw_speed} = $raw_speed->{$idx};
  }

  my $err_cause = $snmp->i_err_disable_cause || {};

  foreach my $idx (keys %$err_cause) {
    my $port = $interfaces->{$idx} or next;
    if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] properties/errdis - local port %s already skipped, ignoring',
          $device->ip, $port;
        next;
    }

    $properties{ $port }->{error_disable_cause} = $err_cause->{$idx};
  }

  my $faststart = $snmp->i_faststart_enabled || {};

  foreach my $idx (keys %$faststart) {
    my $port = $interfaces->{$idx} or next;
    if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] properties/faststart - local port %s already skipped, ignoring',
          $device->ip, $port;
        next;
    }

    $properties{ $port }->{faststart} = $faststart->{$idx};
  }

  my $c_if  = $snmp->c_if  || {};
  my $c_cap = $snmp->c_cap || {};
  my $c_platform = $snmp->c_platform || {};

  my $rem_media_cap = $snmp->lldp_media_cap || {};
  my $rem_vendor = $snmp->lldp_rem_vendor || {};
  my $rem_model  = $snmp->lldp_rem_model  || {};
  my $rem_os_ver = $snmp->lldp_rem_sw_rev || {};
  my $rem_serial = $snmp->lldp_rem_serial || {};

  foreach my $idx (keys %$c_if) {
    my $port = $interfaces->{ $c_if->{$idx} } or next;
    if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] properties/lldpcap - local port %s already skipped, ignoring',
          $device->ip, $port;
        next;
    }

    my $remote_cap  = $c_cap->{$idx} || [];
    my $remote_type = Encode::decode('UTF-8', $c_platform->{$idx} || '');

    $properties{ $port }->{remote_is_wap} = 'true'
      if scalar grep {match_to_setting($_, 'wap_capabilities')} @$remote_cap
         or match_to_setting($remote_type, 'wap_platforms');

    $properties{ $port }->{remote_is_phone} = 'true'
      if scalar grep {match_to_setting($_, 'phone_capabilities')} @$remote_cap
         or match_to_setting($remote_type, 'phone_platforms');

    next unless scalar grep {defined && m/^inventory$/} @{ $rem_media_cap->{$idx} };

    $properties{ $port }->{remote_vendor} = $rem_vendor->{ $idx };
    $properties{ $port }->{remote_model}  = $rem_model->{ $idx };
    $properties{ $port }->{remote_os_ver} = $rem_os_ver->{ $idx };
    $properties{ $port }->{remote_serial} = $rem_serial->{ $idx };
  }

  foreach my $idx (keys %$interfaces) {
    my $port = $interfaces->{$idx} or next;
    if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] properties/ifindex - local port %s already skipped, ignoring',
          $device->ip, $port;
        next;
    }

    $properties{ $port }->{ifindex} = $idx;
  }

  return Status->info(" [$device] no port properties to record")
    unless scalar keys %properties;

  schema('netdisco')->txn_do(sub {
    my $gone = $device->properties_ports->delete;
    debug sprintf ' [%s] properties - removed %d ports with properties',
      $device->ip, $gone;
    $device->properties_ports->populate(
      [map {{ port => $_, %{ $properties{$_} } }} keys %properties] );

    return Status->info(sprintf ' [%s] properties - added %d new port properties',
      $device->ip, scalar keys %properties);
  });
});

true;
