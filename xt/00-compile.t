#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
  use FindBin;
  FindBin::again();

  use Path::Class;

  # stuff useful locations into @INC and $PATH
  unshift @INC,
    dir($FindBin::RealBin)->parent->subdir('lib')->stringify,
    dir($FindBin::RealBin, 'lib')->stringify;

  $ENV{DANCER_ENVDIR} = '/dev/null';
}

# for netdisco app config
use App::Netdisco;
use Test::Compile;

my $test = Test::Compile->new();

my @plfiles = grep {$_ !~ m/(?:graph)/i} $test->all_pl_files();
my @pmfiles = grep {$_ !~ m/(?:graph)/i} $test->all_pm_files();

$test->ok($test->pl_file_compiles($_), "$_ compiles") for @plfiles;
$test->ok($test->pm_file_compiles($_), "$_ compiles") for @pmfiles;

$test->done_testing();
