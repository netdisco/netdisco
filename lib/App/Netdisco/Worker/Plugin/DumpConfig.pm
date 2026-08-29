package App::Netdisco::Worker::Plugin::DumpConfig;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Data::Printer;
use Scalar::Util 'blessed';

# domain_suffix is a compiled Regexp and url_base a URI::Based, and JSON
# encodes neither. Data::Printer renders them, so only the quiet path needs it.
sub _json_safe {
  my $node = shift;
  return $node if !ref $node or ref $node eq 'SCALAR';
  return "$node" if blessed $node;
  return [ map { _json_safe($_) } @$node ] if ref $node eq 'ARRAY';
  return { map {($_ => _json_safe($node->{$_}))} keys %$node }
    if ref $node eq 'HASH';
  return undef;
}

register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my $extra = $job->extra;
  my $print_this_instead = $job->port;

  if (! $ENV{ND2_DO_QUIET}) {
      debug sprintf 'port: "%s"', ($print_this_instead || '');
      debug sprintf 'subaction: "%s"', ($extra || '');
  }

  my $key = ($print_this_instead || $extra);
  my $CONFIG = config();

  # Job promotes an undefined subaction to empty string, so an unkeyed
  # dumpconfig arrives here as q{} and must still dump everything.
  my $dump = (((defined $key) and (ref $key eq q{}) and (length $key))
    ? $CONFIG->{$key} : $CONFIG);
  p $dump unless $ENV{ND2_DO_QUIET};

  return Status->done($ENV{ND2_DO_QUIET}
    ? to_json(_json_safe($dump)) : 'Dumped config');
});

true;
