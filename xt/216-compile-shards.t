#!/usr/bin/env perl

# The compile check is split across xt/00-compile-N.t. These make sure the
# split loses no file and checks none twice.

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::Compile qw(shard_files);

my @files = map { "lib/F$_.pm" } reverse 1 .. 11;

subtest 'shardFiles__four_shards__cover_every_file_exactly_once' => sub {
  my @seen = map { shard_files($_, 4, @files) } 1 .. 4;
  is_deeply([sort @seen], [sort @files], 'the shards together hold every file once');
};

subtest 'shardFiles__unsorted_input__is_independent_of_input_order' => sub {
  is_deeply([shard_files(2, 4, @files)], [shard_files(2, 4, reverse @files)],
    'a shard holds the same files whatever order they arrive in');
};

subtest 'shardFiles__fewer_files_than_shards__leaves_later_shards_empty' => sub {
  is_deeply([shard_files(1, 4, 'lib/A.pm')], ['lib/A.pm'], 'the first shard takes the file');
  is_deeply([shard_files(4, 4, 'lib/A.pm')], [], 'the last shard has nothing to check');
};

subtest 'shardFiles__shard_outside_range__dies_naming_the_range' => sub {
  for my $bad (0, 5, 'x') {
    eval { shard_files($bad, 4, @files) };
    like($@, qr/^shard must be between 1 and 4, not \Q$bad\E/, "shard '$bad' is refused");
  }
};

done_testing;
