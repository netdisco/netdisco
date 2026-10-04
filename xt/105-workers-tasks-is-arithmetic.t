#!/usr/bin/env perl

# workers.tasks is AUTO with optional arithmetic on the CPU count. The operand
# is parsed as a number, never run as Perl.

use strict;
use warnings;

use Test::More 0.88;

use MCE::Util ();
use App::Netdisco::Util::MCE 'parse_max_workers';

my $ncpu = MCE::Util::get_ncpu();
plan skip_all => 'MCE::Util::get_ncpu found no CPUs' unless $ncpu;

subtest 'parse_max_workers__auto_with_each_operator__scales_the_cpu_count' => sub {
  is parse_max_workers('AUTO * 2'),   int($ncpu * 2 + 0.5),   'AUTO * 2';
  is parse_max_workers('auto*1.5'),   int($ncpu * 1.5 + 0.5), 'auto*1.5';
  is parse_max_workers('AUTO / 2.0'), int($ncpu / 2 + 0.5),   'AUTO / 2.0';
  is parse_max_workers('AUTO + 3'),   $ncpu + 3,              'AUTO + 3';
  is parse_max_workers('AUTO - 1'),   $ncpu - 1,              'AUTO - 1';
  is parse_max_workers('AUTO * 2 '),  int($ncpu * 2 + 0.5),   'trailing space';
};

subtest 'parse_max_workers__plain_value__is_returned_as_given' => sub {
  is parse_max_workers('4'),   4, 'a number';
  is parse_max_workers('0'),   0, 'zero';
  is parse_max_workers(undef), 0, 'undef';
};

subtest 'parse_max_workers__operand_carrying_perl_code__runs_none_of_it' => sub {
  our $ran;
  my $workers = parse_max_workers(q{AUTO * 0); $main::ran = 1; #});
  ok !defined $ran, 'the operand was not run';
  is $workers, 0, 'and counts for no workers';
};

subtest 'parse_max_workers__operand_that_is_not_a_number__counts_for_no_workers' => sub {
  is parse_max_workers('AUTO * foo'),   0, 'a bareword';
  is parse_max_workers('AUTO * 2 * 3'), 0, 'a second operator';
  is parse_max_workers('AUTO / 0.0'),   0, 'division by zero';
};

subtest 'parse_max_workers__documented_forms__give_the_expected_count' => sub {
  my %expected = (
    'auto'     => 'auto',
    'auto*1.5' => int($ncpu * 1.5 + 0.5),
    'auto/2.0' => int($ncpu / 2.0 + 0.5),
    'auto+3'   => $ncpu + 3,
    'auto-1'   => $ncpu - 1,
    '4'        => 4,
  );
  foreach my $form (sort keys %expected) {
      is parse_max_workers($form), $expected{$form},
        "parse_max_workers__${form}__gives_the_same_count";
  }
};

done_testing;
