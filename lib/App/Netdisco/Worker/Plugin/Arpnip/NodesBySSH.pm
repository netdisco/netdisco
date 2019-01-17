package App::Netdisco::Worker::Plugin::Arpnip::NodesBySSH;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Node qw/check_mac store_arp/;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';
use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';
use Module::Load ();
use Net::OpenSSH;

# TBD Added Net::OpenSSH and Expect to base requirements instead of recommended, ok?

# TBD use device_auth over the old sshcollector setting? Kind of recommends itself since
# the Worker::Plugin loader checks for available auth there?

# TBD what would be the migration scenario for device_auth <> sshcollector migration? 
# Hard cut or support both for a few releases? Same question for the old bin/netdisco-sshcollector


use Data::Dumper;

register_worker({ phase => 'main', driver => 'cli' }, sub {
  my ($job, $workerconf) = @_;

  my $device = $job->device;
  info sprintf ' [%s] arpnip ssh - evaluating work', $device->ip;

  # TBD setting('device_auth') can probably return multiple items even after the tag filter,
  # how do we pick the most relevant stanza?
  # TBD maybe just reading device_auth is too simplistic and we should implement 
  # Transport::CLI similar to Transport::SNMP to obtain the connection?
  my $device_auth = [grep { $_->{tag} eq "sshcollector" } @{setting('device_auth')}];

  # TBD should there be a setting to skip later snmp-based arpnip
  # If yes, how can this be implemented in the plugin/phase model? Override seems to 
  # depend on using same plugin name (in the X namespace)

  debug sprintf " [%s] arpnip ssh - device_auth\n[%s]", $device->ip, Dumper($device_auth);

  my $now = 'to_timestamp('. (join '.', gettimeofday) .')';

  get_arps($device, $device_auth->[0]);

  $device->update({last_arpnip => \$now});
  my $endmsg = "Ended ssh arpnip for $device, maybe skipping snmp?"; 
  info sprintf " [%s] arpnip ssh - $endmsg", $device->ip;
  return Status->done($endmsg);

});


sub get_arps {
    my ($device, $device_auth) = @_;
    info sprintf " [%s] arpnip ssh - real work now", $device->ip;

    
    my $ssh = Net::OpenSSH->new(
        $device->ip,
        user => $device_auth->{username},
        password => $device_auth->{password},
        timeout => 30,
        async => 0,
        default_stderr_file => '/dev/null',
        master_opts => [
            -o => "StrictHostKeyChecking=no",
            -o => "BatchMode=no"
        ],
    );

    my $class = "App::Netdisco::SSHCollector::Platform::".$device_auth->{platform};
    debug sprintf " [%s] arpnip ssh - delegating to %s", $device->ip, $class;
    Module::Load::load $class;

    my $platform_class = $class->new();

    # TBD device_auth will need the extra args for sshcollector modules documented/updated
    # stanza example:
    #  - tag: sshcollector
    #    driver: cli
    #    platform: IOS
    #    skip_snmp_arpnip: true
    #    only:
    #        - 'lab19.megacorp.za'
    #    username: netdisco
    #    password: hunter2
    # 
    # platform: the SSHCollector class
    # platform-specific extra keys:
    # Platform/ASA.pm:           $expect->send( $args->{enable_password} ."\n" );
    # Platform/CPVSX.pm:         $expect->send( $args->{expert_password} ."\n" );
    # Platform/FreeBSD.pm:       my $command = ($args->{arp_command} || 'arp');
    # Platform/GAIAEmbedded.pm:  my $command = ($args->{arp_command} || 'arp');
    # Platform/Linux.pm:         my $command = ($args->{arp_command} || 'arp');

    my $arpentries = [ $platform_class->arpnip($device->ip, $ssh, $device_auth) ];

    if (not scalar @$arpentries) {
        warning sprintf " [%s] WARNING: no entries received from device", $device->ip;
    }

    hostnames_resolve_async($arpentries);

    foreach my $arpentry ( @$arpentries ) {

        # skip broadcast/vrrp/hsrp and other weirdos
        next unless check_mac( $arpentry->{mac} );

        debug sprintf ' [%s]   arpnip ssh - stored entry: %s / %s / %s',
            $device->ip, $arpentry->{mac}, $arpentry->{ip}, $arpentry->{dns};
        store_arp({
            node => $arpentry->{mac},
            ip => $arpentry->{ip},
            dns => $arpentry->{dns},
        });
    }

}

true;
