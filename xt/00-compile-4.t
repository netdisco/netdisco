#!/usr/bin/env perl

# compiles one quarter of the files; see Test::Netdisco::Compile

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
use Test::Netdisco::Compile qw(compile_shard);

compile_shard(4, 4);
