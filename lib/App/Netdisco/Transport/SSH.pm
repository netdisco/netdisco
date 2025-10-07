package App::Netdisco::Transport::SSH;

use Dancer qw/:syntax :script/;

use App::Netdisco::Util::Device 'get_device';
use Module::Load ();
use Net::OpenSSH;
use Try::Tiny;

use base 'Dancer::Object::Singleton';

=head1 NAME

App::Netdisco::Transport::SSH

=head1 DESCRIPTION

Returns an object which has an active SSH connection which can be used
for some actions such as arpnip.

 my $cli = App::Netdisco::Transport::SSH->session_for( ... );

=cut

__PACKAGE__->attributes(qw/ sessions /);

sub init {
  my ( $class, $self ) = @_;
  $SIG{CHLD} = 'IGNORE';
  $self->sessions( {} );
  return $self;
}

=head1 session_for( $ip )

Given an IP address, returns an object instance configured for and connected
to that device.

Returns C<undef> if the connection fails.

=cut

{
  package MySession;
  use Moo;

  has 'ssh'  => ( is => 'rw' );
  has 'auth' => ( is => 'rw' );
  has 'host' => ( is => 'rw' );
  has 'platform' => ( is => 'rw' );

  sub arpnip {
    my $self = shift;
    $self->platform->arpnip(@_, $self->host, $self->ssh, $self->auth)
      if $self->platform->can('arpnip');
  }

  sub macsuck {
    my $self = shift;
    $self->platform->macsuck(@_, $self->host, $self->ssh, $self->auth)
      if $self->platform->can('macsuck');
  }

  sub subnets {
    my $self = shift;
    $self->platform->subnets(@_, $self->host, $self->ssh, $self->auth)
        if $self->platform->can('subnets');
  }
}

sub session_for {
  my ($class, $ip) = @_;

  my $device = get_device($ip) or return undef;
  my $sessions = $class->instance->sessions or return undef;

  return $sessions->{$device->ip} if exists $sessions->{$device->ip};
  debug sprintf 'cli session cache warm: [%s]', $device->ip;

  my $auth = (setting('device_auth') || []);
  if (1 != scalar @$auth) {
    error sprintf " [%s] require only one matching auth stanza", $device->ip;
    return undef;
  }
  $auth = $auth->[0];

  if (!defined $auth->{platform}) {
    error sprintf " [%s] Perl SSH platform not specified, assuming Python", $device->ip;
    return undef;
  }

  my @master_opts = qw(-o BatchMode=no);
  push(@master_opts, @{$auth->{ssh_master_opts}})
    if $auth->{ssh_master_opts};

  $Net::OpenSSH::debug = $ENV{SSH_TRACE};
  my $ssh = Net::OpenSSH->new(
    $device->ip,
    user => $auth->{username},
    password => $auth->{password},
    key_path => $auth->{key_path},
    passphrase => $auth->{passphrase},
    port => $auth->{port},
    batch_mode => $auth->{batch_mode},
    timeout => $auth->{timeout} ? $auth->{timeout} : 30,
    async => 0,
    default_stderr_file => '/dev/null',
    master_opts => \@master_opts
  );

  if ($ssh->error) {
    error sprintf " [%s] ssh connection error [%s]", $device->ip, $ssh->error;
    return undef;
  }
  elsif (! $ssh) {
    error sprintf " [%s] Net::OpenSSH instantiation error", $device->ip;
    return undef;
  }

  my $platform = "App::Netdisco::SSHCollector::Platform::" . $auth->{platform};
  my $happy = false;
  try {
    Module::Load::load $platform;
    $happy = true;
  } catch { error $_ };
  return unless $happy;

  my $sess = MySession->new(
    ssh  => $ssh,
    auth => $auth,
    host => $device->ip,
    platform => $platform->new(),
  );

  return ($sessions->{$device->ip} = $sess);
}

true;
