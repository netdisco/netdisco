package App::Netdisco::Worker::Plugin::Arpnip::NodesBySSH;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::CLI ();
use App::Netdisco::Util::Node qw/check_mac store_arp/;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';
use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';
use Module::Load ();
use Net::OpenSSH;
use Try::Tiny;

register_worker({ phase => 'main', driver => 'cli' }, sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;

    if (get_arps($device)){
      my $now = 'to_timestamp('. (join '.', gettimeofday) .')';
      $device->update({last_arpnip => \$now});
      my $endmsg = "Ended ssh arpnip for $device"; 
      info sprintf " [%s] arpnip ssh - $endmsg", $device->ip;
      return Status->done($endmsg);
    }else{
      Status->defer("arpnip ssh failed");
    }
  });


sub get_arps {
  my ($device) = @_;

  my ($ssh, $selected_auth) = App::Netdisco::Transport::CLI->session_for($device->ip, "sshcollector");

  unless ($ssh){
    my $msg = "arpnip ssh failed: could not SSH connect to $device, deferring job"; 
    warning sprintf " [%s] arpnip ssh - %s", $device->ip, $msg;
    return undef;
  }

  my $class = "App::Netdisco::SSHCollector::Platform::".$selected_auth->{platform};
  debug sprintf " [%s] arpnip ssh - delegating to platform module %s", $device->ip, $class;

  my $load_failed = 0;
  try {
    Module::Load::load $class;
  } catch {
    warning sprintf " [%s] arpnip ssh - failed to load %s: %s", $device->ip, $class, substr($_, 0, 50)."...";
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

    debug sprintf ' [%s] arpnip ssh - stored entry: %s / %s / %s',
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
