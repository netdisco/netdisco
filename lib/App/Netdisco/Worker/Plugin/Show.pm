package App::Netdisco::Worker::Plugin::Show;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Data::Printer ();
use App::Netdisco::Transport::SNMP;

register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless defined shift->device;
  return Status->done('Show is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $class, $object) = map {$job->$_} qw/device port extra/;

  $class = 'SNMP::Info::'.$class if $class and $class !~ m/^SNMP::Info::/;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device, $class);

  $object ||= 'interfaces';
  my $orig_object = $object;
  my ($mib, $leaf) = split m/::/, $object;
  SNMP::loadModules($mib) if $mib and $leaf and $mib ne $leaf;
  $object =~ s/[-:]/_/g;

  my $result = sub { eval { $snmp->$object() } || ($ENV{ND2_DO_QUIET} ? q{} : undef) };
  my @options = ($ENV{ND2_DO_QUIET} ? (scalar_quotes => undef, colored => 0) : ());

  Data::Printer::p( $result->(), @options );

  return Status->done(
    sprintf "Showed %s response from %s", $orig_object, $device->ip);
});

true;
