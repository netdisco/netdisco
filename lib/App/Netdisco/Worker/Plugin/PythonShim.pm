package App::Netdisco::Worker::Plugin::PythonShim;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;

use App::Netdisco::Util::Python qw/py_worklet/;

sub import {
  my ($pkg, $action) = @_;
  return unless $action;
  _find_python_worklets($action, setting($_))
    for qw/python_worker_plugins extra_python_worker_plugins/;
}

sub _find_python_worklets {
  my ($action, $config) = @_;
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

      shift @parts; # action
      my $phase = pop @parts;

      my %base = (
        action => $action,
        (scalar @parts ? (namespace => join '::', @parts) : ()),
        phase => $phase,
        pyworklet => $worklet,
      );

      if (ref {} eq ref $entry) {
          my $rhs = (values %$entry)[0];
          _register_python_worklet({ %base, driver => $_ }) for @$rhs;
      }
      else {
          _register_python_worklet({ %base });
      }
  }
}

sub _register_python_worklet {
  my $workerconf = shift;

  $ENV{ND2_LOG_PLUGINS} &&
    debug sprintf '...registering python worklet a:%s s:%s p:%s d:%s/p:%s',
      (exists $workerconf->{action}    ? ($workerconf->{action}    || '?') : '-'),
      (exists $workerconf->{namespace} ? ($workerconf->{namespace} || '?') : '-'),
      (exists $workerconf->{phase}     ? ($workerconf->{phase}     || '?') : '-'),
      (exists $workerconf->{driver}    ? ($workerconf->{driver}    || '?') : '-'),
      (exists $workerconf->{priority}  ? ($workerconf->{priority}  || '?') : '-');

  register_worker($workerconf, sub { py_worklet(@_) });
}

true;
