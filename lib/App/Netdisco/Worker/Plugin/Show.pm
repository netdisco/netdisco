package App::Netdisco::Worker::Plugin::Show;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use JSON::PP ();
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

  my $result = sub { eval { $snmp->$object() } };

  if ($ENV{ND2_DO_QUIET}) {
      my $coder = JSON::PP->new->utf8(1)
                               ->allow_nonref(1)
                               ->allow_unknown(1)
                               ->allow_blessed(1)
                               ->allow_bignum(1);
      print $coder->encode( $result->() );
  }
  else {
      Data::Printer::p( $result->() );
  }

  return Status->done(
    sprintf "Showed %s response from %s", $orig_object, $device->ip);
});

true;
