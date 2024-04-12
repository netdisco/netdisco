package App::Netdisco::Worker::Plugin::DumpInfoCache;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Module::Load ();
use Data::Dumper;
use Storable 'dclone';

use App::Netdisco::Transport::SNMP;

register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port, $extra) = map {$job->$_} qw/device port extra/;

  Module::Load::load 'Module::Info';
  Module::Load::load 'Data::Tie::Watch';

  return Status->error('Missing device (-d).') unless $device;
  return Status->error(sprintf "unknown device: %s.", $device)
    unless $device->in_storage;

  return Status->done('Dump info cache is able to run');
});

register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $class, $dumpclass) = map {$job->$_} qw/device port extra/;

  $class = 'SNMP::Info::'.$class if $class and $class !~ m/^SNMP::Info::/;
  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device, $class);
  
  $dumpclass = 'SNMP::Info::'.$dumpclass if $dumpclass and $dumpclass !~ m/^SNMP::Info::/;
  $dumpclass ||= ($snmp->class || $device->snmp_class);

  debug sprintf 'inspecting class %s', $dumpclass;
  my %sh = Module::Info->new_from_loaded($dumpclass)->subroutines;
  my @subs = grep { $_ !~ m/^_/ }
              map { $_ =~ s/^.+:://; $_ }  ## no critic
                  keys %sh;

  my $cache = {};
  my $fetch = sub {
      my($self, $key) = @_;
      my $val = $self->Fetch($key);
      #return $val if !defined $val;

      my @ignore = qw(munge globals funcs Offline store sess debug snmp_ver);
      return $val if scalar grep { $_ eq $key } @ignore;

      (my $stripped = $key) =~ s/^_//;
      if (exists $snmp->{store}->{$stripped}) {
          $cache->{$key} = 1;
          $cache->{store}->{$stripped} = dclone $snmp->{store}->{$stripped};
      }
      return $val if exists $snmp->{store}->{$stripped};
          
      #print "In fetch callback, key=$key\n";
      #Data::Printer::p( $val ); print "\n";

      $cache->{$key} = $val;
      return $val;
  };

  my $watch = Data::Tie::Watch->new(
      -variable => $snmp,
      -fetch    => [$fetch],
  );

  $snmp->$_ for @subs;
  $watch->Unwatch;

  print Dumper( $cache );
  return Status->done(
    sprintf "Dumped %s cache for %s", $dumpclass, $device->ip);
});

true;
