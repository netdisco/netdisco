package App::Netdisco::Worker::Plugin::PythonShim;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;

use App::Netdisco::Util::Python qw/py_worklet/;

sub import {
  my ($pkg, $action) = @_;
  return unless $action;
  _find_python_worklets($action, $_)
    for qw/python_worker_plugins extra_python_worker_plugins/;
}

sub _find_python_worklets {
  my ($action, $setting) = @_;
  my $config = setting($setting);
  return unless $config and ref [] eq ref $config;

  foreach my $entry (@{ $config }) {
      my $worklet = undef;
      if (ref {} eq ref $entry) {
          $worklet = (keys %$entry)[0];
      }
      else {
          $worklet = $entry;
      }
      next unless $worklet and $worklet =~ m/^${action}\./;
      my @parts = split /\./, $worklet;

      my %base = (
        action => shift @parts,
        pyworklet => ($setting =~ m/extra/ ? setting('extra_python_worker_package_namespace') : 'netdisco')
      );
      my %phases = (map {$_ => ''} qw(check early main user store late));

      while (my $phase = shift @parts) {
          if (exists $phases{$phase}) {
              $base{phase} = $phase;
              last;
          }
          else {
              push @{ $base{namespace} }, $phase;
          }
      }

      if (scalar @parts and exists setting('driver_priority')->{$parts[0]}) {
          $base{driver} = shift @parts;
      }

      $base{platform} = [ @parts ] if scalar @parts;

      if (ref {} eq ref $entry) {
          my $rhs = (values %$entry)[0];
          if (ref [] eq ref $rhs) {
              foreach my $driver (@{ $rhs }) {
                  _register_python_worklet({ %base, driver => $driver });
              }
          }
          else {
              _register_python_worklet({ %base, %$rhs });
          }
      }
      else {
          _register_python_worklet({ %base });
      }
  }
}

sub _register_python_worklet {
  my $workerconf = shift;
  $workerconf->{pyworklet} .= _build_pyworklet(%$workerconf);
  $workerconf->{namespace} = join '::', @{ $workerconf->{namespace} }
    if exists $workerconf->{namespace};

  $ENV{ND2_LOG_PLUGINS} &&
    debug sprintf '...registering python worklet a:%s s:%s p:%s d:%s/p:%s',
      (exists $workerconf->{action}    ? ($workerconf->{action}    || '?') : '-'),
      (exists $workerconf->{namespace} ? ($workerconf->{namespace} || '?') : '-'),
      (exists $workerconf->{phase}     ? ($workerconf->{phase}     || '?') : '-'),
      (exists $workerconf->{driver}    ? ($workerconf->{driver}    || '?') : '-'),
      (exists $workerconf->{priority}  ? ($workerconf->{priority}  || '?') : '-');

  register_worker($workerconf, sub { py_worklet(@_) });
}

sub _build_pyworklet {
  my %base = @_;
  return join '.', '', 'worklet',
    $base{action},
    (exists $base{namespace} ? @{ $base{namespace} } : ()),
    $base{phase},
    (exists $base{driver} ? $base{driver} : ()),
    (exists $base{platform} ? @{ $base{platform} } : ());
}

true;
