package Test::Netdisco::Compile;

# xt/00-compile-N.t each check one share of the files, because checking a
# file starts a fresh perl, and one test checking all 300-odd files was the
# longest test by far: no number of parallel harness jobs could finish sooner.

use strict;
use warnings;

use Exporter 'import';
use Test::Compile::Internal;

our @EXPORT_OK = qw(shard_files compile_shard);

sub shard_files {
  my ($shard, $shards, @files) = @_;
  die "shard must be between 1 and $shards, not $shard\n"
    unless $shard =~ m/^\d+$/ and $shard >= 1 and $shard <= $shards;

  my @sorted = sort @files;
  return @sorted[ grep { $_ % $shards == $shard - 1 } 0 .. $#sorted ];
}

sub compile_shard {
  my ($shard, $shards) = @_;
  my $test = Test::Compile::Internal->new();

  my @plfiles = shard_files($shard, $shards,
    grep { $_ !~ m/(?:graph)/i } $test->all_pl_files());
  my @pmfiles = shard_files($shard, $shards,
    grep { $_ !~ m/(?:graph)/i } $test->all_pm_files());

  $test->ok($test->pl_file_compiles($_), "$_ compiles") for @plfiles;
  $test->ok($test->pm_file_compiles($_), "$_ compiles") for @pmfiles;

  $test->done_testing();
}

1;
