package App::Netdisco::Util::Daemon;

use strict;
use warnings;

use MCE::Util ();

# make sure this is already done elsewhere
use if $^O eq 'linux', 'Sys::Proctitle';

use base 'Exporter';
our @EXPORT = qw/prctl parse_max_workers/;

sub prctl {
  if ($^O eq 'linux') {
      Sys::Proctitle::setproctitle(shift);
  }
  else {
      $0 = shift;
  }
}

sub parse_max_workers {
  my $max = shift;
  return 0 if !defined $max;

  if ($max =~ /^auto(?:$|\s*([\-\+\/\*])\s*(.+)$)/i) {
      my $ncpu = MCE::Util::get_ncpu() || 0;

      if ($1 and $2) {
          local $@; $max = eval "int($ncpu $1 $2 + 0.5)";
      }
  }

  return $max || 0;
}

1;
