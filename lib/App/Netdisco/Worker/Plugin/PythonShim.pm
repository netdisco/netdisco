package App::Netdisco::Worker::Plugin::PythonShim;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;

use App::Netdisco::Util::Python qw/py_worklet/;

sub import {
  my ($pkg, $action) = @_;
  return unless $action;
  _find_python_worklets($action, setting($_)->{$action})
    for qw/python_worker_plugins extra_python_worker_plugins/;
}

sub _find_python_worklets {
  my ($action, $config) = @_;
  return unless $config;

  # here contains some magic rules about python worker spec in config
  # if action has no stages, then run it in main phase
  # if action has stages, call check phase on action namespace
  # stages MAY have dict of phases or scalar; otherwise main phase is used
  # phases MAY have list of drivers; otherwise priority 0 is used

  if (0 == scalar keys %{ $config }) {
    _register_python_worklet({action => $action, phase => 'main'});
  }
  else {
      _register_python_worklet({action => $action, phase => 'check'});

      foreach my $stage (sort keys %{ $config }) {
          if (!defined $config->{$stage} or
                  (ref {} eq ref $config->{$stage}
                    and 0 == scalar keys %{ $config->{$stage} })) {
              _register_python_worklet({action => $action,
                namespace => $stage, phase => 'main'});
          }
          elsif (ref q{} eq ref $config->{$stage}) {
              _register_python_worklet({action => $action,
                namespace => $stage, phase => $config->{$stage}});
          }
          else {
              foreach my $phase (sort keys %{ $config->{$stage} }) {
                  my @drivers = @{ $config->{$stage}->{$phase} || [] };

                  _register_python_worklet({action => $action,
                    namespace => $stage, phase => $phase})
                      if 0 == scalar @drivers;

                  _register_python_worklet({action => $action,
                    namespace => $stage, phase => $phase, driver => $_})
                      for @drivers;
              }
          }
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
