package App::Netdisco::Util::Daemon;

use strict;
use warnings;

# make sure this is already done elsewhere
use if $^O eq 'linux', 'Sys::Proctitle';

use base 'Exporter';
our @EXPORT = 'prctl';

sub prctl {
  if ($^O eq 'linux') {
      Sys::Proctitle::setproctitle(shift);
  }
  else {
      $0 = shift;
  }
}

1;
