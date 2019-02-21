package App::Netdisco::Transport::CLI;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Permission ':all';
use Module::Load ();
use Path::Class 'dir';
use NetAddr::IP::Lite ':lower';
use List::Util qw/pairkeys pairfirst/;

use base 'Dancer::Object::Singleton';

=head1 NAME

App::Netdisco::Transport::CLI

=head1 DESCRIPTION

Singleton for CLI connections modelled after L<App::Netdisco::Transport::SNMP> but currently 
with minimal functionality. Returns a L<Net::OpenSSH> instance for a given device IP. Limited 
to device_auth stanzas tagged sshcollector. Always returns a new connection which the caller 
is supposed to close (or it will be closed when going out of scope)

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

  my $device_auth = [grep { $_->{tag} eq $tag } @{setting('device_auth')}];

  # Currently just the first match is used. Warn if there are more.
  my $selected_auth = $device_auth->[0];

  if (@{$device_auth} > 1){
    warning sprintf " [%s] Transport::CLI - found %d matching entries in device_auth, using the first one", 
      $device->ip, scalar @{$device_auth};
  }

  my @master_opts = qw(-o BatchMode=no);
  push(@master_opts, @{$selected_auth->{ssh_master_opts}}) if $selected_auth->{ssh_master_opts};

  my $ssh = Net::OpenSSH->new(
    $device->ip,
    user => $selected_auth->{username},
    password => $selected_auth->{password},
    timeout => 30,
    async => 0,
    default_stderr_file => '/dev/null',
    master_opts => \@master_opts
  );

  my $CONFIG = config();
  $Net::OpenSSH::debug = ~0 if $CONFIG->{log} eq 'debug';

  if ($ssh->error){
    error sprintf " [%s] Transport::CLI - ssh connection error [%s]", $device->ip, $ssh->error;
    return undef;
  }elsif (!$ssh){
    error sprintf " [%s] Transport::CLI - Net::OpenSSH instantiation error", $device->ip;
    return undef;
  }else{
    return ($ssh, $selected_auth);
  }
}

true;
