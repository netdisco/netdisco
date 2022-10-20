package App::Netdisco::Worker::Plugin::Macsuck::PortAccessEntity;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';
use Data::Dumper;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Worker;
use App::Netdisco::Util::Permission qw/check_acl_no check_acl_only/;

register_worker({ phase => 'early', driver => 'snmp' }, sub {

  no warnings "uninitialized";
  my ($job, $workerconf) = @_;
  my $count = 0;
  my $device = $job->device;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("pae failed: could not SNMP connect to $device");
  my $interfaces = $snmp->interfaces;
  debug sprintf ' [%s] pae - updating PortAccessEntity details for %s', $device->ip, $device->dns;

  # device property
  my $pae_control = $snmp->pae_control();

  if ($pae_control) {
        schema('netdisco')->resultset('Device')->search({ 'me.ip' => $device->ip})
          ->update({ pae_control => $pae_control });
    debug sprintf ' [%s] pae - PortAccessEntity device-wide support: %s', $device->ip, $pae_control;
  } else {
    debug sprintf ' [%s] pae - no PortAccessEntity support, leaving worker', $device->ip;
    return Status->info("Skipped pae for $device");
  }

  # individual port properties
  my $pae_authconfig_state = $snmp->pae_authconfig_state();
  my $pae_authconfig_port_status = $snmp->pae_authconfig_port_status();
  my $pae_authsess_user = $snmp->pae_authsess_user();
  my $pae_authsess_mab = $snmp->pae_authsess_mab();
  my $pae_capabilities = $snmp->pae_i_capabilities();
  my $capdesc = { 'dot1xPaePortAuthCapable' => , 'Authenticator functions are supported',
   'dot1xPaePortSuppCapable' => , 'Supplicant functions are supported'};
  my $pae_last_eapol_frame_source = $snmp->pae_i_last_eapol_frame_source();

  for my $ind (sort keys $interfaces){
    my $capstr = $pae_capabilities->{$ind} ? ($pae_capabilities->{$ind} . " - " . $capdesc->{$pae_capabilities->{$ind}}) : ""; 
    debug sprintf ' [%s] pae - attributes found %s %s %s %s %s %s %s', 
      $device->ip, $ind, 
      $pae_authconfig_state->{$ind} || 'no pae_authconfig_state', 
      $pae_authconfig_port_status->{$ind}, 
      $pae_authsess_user->{$ind}, 
      $pae_authsess_mab->{$ind}, 
      $capstr, 
      $pae_last_eapol_frame_source->{$ind};

    schema('netdisco')->resultset('DevicePortProperties')
          ->search({ 'me.ip' => $device->ip, 'me.port' => $interfaces->{$ind} })
          ->update({ 
            pae_authconfig_state          => $pae_authconfig_state->{$ind} ,
            pae_authconfig_port_status    => $pae_authconfig_port_status->{$ind} ,
            pae_authsess_user             => $pae_authsess_user->{$ind} ,
            pae_authsess_mab              => $pae_authsess_mab->{$ind} ,
            pae_capabilities              => $capstr,
            pae_last_eapol_frame_source   => $pae_last_eapol_frame_source->{$ind} ,
            
        });
  }

  return Status->info("Completed pae for $device");
});

true;
