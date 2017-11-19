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
  my ($device, $port, $extra) = map {$job->$_} qw/device port extra/;

  $extra ||= 'interfaces'; my $class = undef;
  ($class, $extra) = split(/::([^:]+)$/, $extra);
  if ($class and $extra) {
      $class = 'SNMP::Info::'.$class;
  }
  else {
      $extra = $class;
      undef $class;
  }

  my $i = App::Netdisco::Transport::SNMP->reader_for($device, $class);
  Data::Printer::p($i->$extra($port));

  return Status->done(
    sprintf "Showed %s response from %s", $extra, $device->ip);
});

true;
