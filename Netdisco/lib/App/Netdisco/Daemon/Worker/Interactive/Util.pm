package App::Netdisco::Daemon::Worker::Interactive::Util;

# support utilities for Daemon Actions

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ done error /;
our %EXPORT_TAGS = (
  all => [qw/ done error /],
);

sub done  { return ('done',  shift) }
sub error { return ('error', shift) }

1;
