package App::Netdisco::Daemon::Util;

use strict;
use warnings;

# support utilities for Daemon Actions

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ job_done job_error job_defer /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub job_done  { return ('done',  shift) }
sub job_error { return ('error', shift) }
sub job_defer { return ('defer', shift) }

1;
