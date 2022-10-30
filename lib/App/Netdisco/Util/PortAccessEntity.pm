package App::Netdisco::Util::PortAccessEntity;

use Dancer qw/:syntax/;
use Dancer::Plugin::DBIC 'schema';
use aliased 'App::Netdisco::Worker::Status';


use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/update_pae_attributes/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::PortAccessEntity

=head1 DESCRIPTION

Helper subroutines to update PAE details in device_port_properties
These are updated both during discover and macsuck.

=cut

sub update_pae_attributes {
  my ($device) = @_;
  no warnings "uninitialized";

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->defer("pae failed: could not SNMP connect to $device");
  debug sprintf ' [%s] pae - updating PortAccessEntity details', $device->ip;

  # device property
  my $pae_control = $snmp->pae_control();

  if ($pae_control and $pae_control eq 'enabled') {
    debug sprintf ' [%s] pae - PortAccessEntity device-wide support: %s', $device->ip, $pae_control;
    schema('netdisco')->resultset('Device')->search({ 'me.ip' => $device->ip})
          ->update({ pae_is_enabled => 't' });
  } else {
    debug sprintf ' [%s] pae - no PortAccessEntity support, leaving worker', $device->ip;
    schema('netdisco')->resultset('Device')->search({ 'me.ip' => $device->ip})
          ->update({ pae_is_enabled => 'f' });
    return Status->info("Skipped pae for $device");
  }

  # individual port properties
  my $interfaces = $snmp->interfaces;
  my $pae_authconfig_state        = $snmp->pae_authconfig_state();
  my $pae_authconfig_port_control = $snmp->dot1xAuthAuthControlledPortControl();
  my $pae_authconfig_port_status  = $snmp->pae_authconfig_port_status();
  my $pae_authsess_user           = $snmp->pae_authsess_user();
  my $pae_authsess_mab            = $snmp->pae_authsess_mab();
  my $pae_capabilities            = $snmp->pae_i_capabilities();
  my $pae_last_eapol_frame_source = $snmp->pae_i_last_eapol_frame_source();

  foreach my $ind (sort keys %$interfaces){
    debug sprintf ' [%s] pae - attributes found for ifindex %s: %s %s %s %s %s %s %s', 
      $device->ip, $ind, 
      $pae_authconfig_state->{$ind} || 'no pae_authconfig_state', 
      $pae_authconfig_port_control->{$ind}, 
      $pae_authconfig_port_status->{$ind}, 
      $pae_authsess_user->{$ind}, 
      $pae_authsess_mab->{$ind}, 
      $pae_capabilities->{$ind},
      $pae_last_eapol_frame_source->{$ind};

    schema('netdisco')->resultset('DevicePortProperties')
          ->search({ 'me.ip' => $device->ip, 'me.port' => $interfaces->{$ind} })
          ->update({ 
            pae_authconfig_state          => $pae_authconfig_state->{$ind} ,
            pae_authconfig_port_control   => $pae_authconfig_port_control->{$ind} ,
            pae_authconfig_port_status    => $pae_authconfig_port_status->{$ind} ,
            pae_authsess_user             => $pae_authsess_user->{$ind} ,
            pae_authsess_mab              => $pae_authsess_mab->{$ind} ,
            pae_is_authenticator          => $pae_capabilities->{$ind} =~ m/dot1xPaePortAuthCapable/ ? "t" : "f",
            pae_is_supplicant             => $pae_capabilities->{$ind} =~ m/dot1xPaePortSuppCapable/ ? "t" : "f",
            pae_last_eapol_frame_source   => $pae_last_eapol_frame_source->{$ind} ,
            
        });
  }

  return Status->info("Completed pae for $device");
} 

1;
