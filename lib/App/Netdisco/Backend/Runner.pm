package App::Netdisco::Backend::Runner;

use Dancer ':moose :syntax';
use App::Netdisco::Worker::Status;

use Try::Tiny;
use Role::Tiny;
use namespace::clean;

# mixin code to run workers loaded via plugins
sub run {
  return App::Netdisco::Worker::Status->new({done => true, message => 'ok'});
}

true;
