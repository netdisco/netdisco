package App::Netdisco::Transport::CLI;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Permission ':all';

use Try::Tiny;
use Module::Load ();
use Path::Class 'dir';
use NetAddr::IP::Lite ':lower';
use List::Util qw/pairkeys pairfirst/;
use Data::Dumper;

use base 'Dancer::Object::Singleton';

=head1 NAME

App::Netdisco::Transport::CLI

=head1 DESCRIPTION

Singleton for CLI connections modelled after L<App::Netdisco::Transport::SNMP> but currently with minimal functionality. Returns a L<Net::OpenSSH> instance for a
given device IP. Limited to device_auth stanzas tagged sshcollector. Always returns a new connection which the caller is supposed to close.

 App::Netdisco::Transport::CLI->session_for( ... );

=cut


sub init {
  my ( $class, $self ) = @_;
  return $self;
}

=head1 session_for( $ip, $tag )

Given an IP address and a tag, returns an L<Net::OpenSSH> instance configured for and
connected to that device, as well as the C<device_auth> entry that was chosen for the device.  

Returns C<undef> if the connection fails.

=cut

sub session_for {
  my ($class, $ip, $tag) = @_;
  my $device = get_device($ip) or return undef;

  # TBD device_auth will need the extra args for sshcollector modules documented/updated
  # stanza example:
  #  - tag: sshcollector
  #    driver: cli
  #    platform: IOS
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
  #

  # TBD Somehow this already seems to return records matching the "only" attribute, how?
  my $device_auth = [grep { $_->{tag} eq $tag  && $_->{driver} eq "cli" } @{setting('device_auth')}];
  debug sprintf " [%s] Transport::CLI - device_auth\n[%s]", $device->ip, Dumper($device_auth);

  #foreach my $d (@{$device_auth}) {
  #  if (check_acl_no($device, $d->{only})){
  #    debug sprintf " [%s] Transport::CLI - device_auth\n[%s] matches", $device->ip, Dumper($d);
  #  }else{
  #    debug sprintf " [%s] Transport::CLI - device_auth\n[%s] ignored", $device->ip, Dumper($d);
  #  } 
  #}

  # TBD currently just the first match is returned. How to select the "best match" (e.g. longest mask)
  my $selected_auth = $device_auth->[0];

  my $ssh = Net::OpenSSH->new(
    $device->ip,
    user => $selected_auth->{username},
    password => $selected_auth->{password},
    timeout => 30,
    async => 0,
    default_stderr_file => '/dev/null',
    master_opts => [
      -o => "StrictHostKeyChecking=no",
      -o => "BatchMode=no"
    ],
  );

  if ($ssh->error){
    warn sprintf " [%s] Transport::CLI - ssh connection error [%s]", $device->ip, $ssh->error;
    return undef;
  }else{
    return ($ssh, $selected_auth);
  }
}

true;
