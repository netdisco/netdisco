package App::Netdisco::Worker::Plugin::CheckConfig;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;

use App::Netdisco::Util::Python qw/py_worker/;

register_worker({ phase => 'main' }, sub {
  return py_worker('linter', @_);
});

true;
