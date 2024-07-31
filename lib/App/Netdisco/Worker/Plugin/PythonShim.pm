package App::Netdisco::Worker::Plugin::PythonShim;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;

use App::Netdisco::Util::Python qw/py_worker/;

sub import {
  my ($pkg, $action) = @_;
  return unless $action;
  _register_python_workers($action, setting($_)->{$action})
    for qw/python_worker_plugins extra_python_worker_plugins/;
}

sub _register_python_workers {
  my ($action, $config) = @_;
  return unless $config;

  foreach my $namespace (keys %{ $config }) {
    foreach my $worker (@{ $config->{$namespace} || [] }) {

      die "missing tag on python_workers when multiple namespace workers are configured"
        if scalar @{ $config->{$namespace} || {} } > 1
           and !exists $worker->{tag};

      $ENV{ND2_LOG_PLUGINS} &&
        debug sprintf '...registering python worker %s.%s%s in %s',
          $action, $namespace,
          (exists $worker->{tag} ? '.'.$worker->{tag} : ''),
          (exists $worker->{phase} ? $worker->{phase} : 'user');

      register_worker({
          action => $action,
          namespace => $namespace,
          %{ $worker },
      }, sub { py_worker(@_) });

    }
  }
}

true;
