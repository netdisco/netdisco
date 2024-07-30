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

  foreach my $stage (keys %{ $config }) {
    foreach my $worker (@{ $config->{$stage} || [] }) {

      die "missing tag on python_workers when multiple stage workers are configured"
        if scalar @{ $config->{$stage} || {} } > 1
           and !exists $worker->{tag};

      $ENV{ND2_LOG_PLUGINS} &&
        debug sprintf '...registering python worker %s%s/%s',
          $stage,
          (exists $worker->{tag} ? '/'.$worker->{tag} : ''),
          (exists $worker->{phase} ? ''.$worker->{phase} : 'main');

      register_worker({
          action => $action,
          namespace => $stage,
          %{ $worker },
      }, sub {
        return py_worker(@_);
      });

    }
  }
}

true;
