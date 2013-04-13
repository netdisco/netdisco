package App::Netdisco::Daemon::Util;

# support utilities for Daemon Actions

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ job_done job_error /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub job_done  { return ('done',  shift) }
sub job_error { return ('error', shift) }

1;
