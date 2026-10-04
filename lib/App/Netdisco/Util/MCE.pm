package App::Netdisco::Util::MCE;

use strict;
use warnings;

use MCE::Util ();

use base 'Exporter';
our @EXPORT = qw/prctl parse_max_workers/;

sub prctl { $0 = shift }

sub parse_max_workers {
  my $max = shift;
  return 0 if !defined $max;

  if ($max =~ /^auto(?:$|\s*([\-\+\/\*])\s*(.+)$)/i) {
      my $ncpu = MCE::Util::get_ncpu() || 0;

      if ($1 and $2) {
          my ($op, $operand) = ($1, $2);
          $max = _scale_ncpu($ncpu, $op, $operand);
      }
  }

  return $max || 0;
}

# the forms MCE itself documents: auto, auto*1.5, auto/2.0, auto+3, auto-1
sub _scale_ncpu {
  my ($ncpu, $op, $operand) = @_;
  return 0 unless $operand =~ m/^(\d+(?:\.\d*)?|\.\d+)\s*$/;
  my $num = $1;

  my $scaled = ($op eq '+') ? $ncpu + $num
             : ($op eq '-') ? $ncpu - $num
             : ($op eq '*') ? $ncpu * $num
             : ($num == 0)  ? 0
             :                $ncpu / $num;

  return int($scaled + 0.5);
}

1;
