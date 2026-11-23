#!/usr/bin/env perl

# Build.PL's SNMP::Info minimum is enforced only by installers. A checkout,
# an operating system package or a stray copy in site Perl gave Netdisco an
# older SNMP::Info without anyone noticing, and features that need a newer
# one, such as incomplete walk protection, turned off quietly. Each module
# that loads SNMP::Info now states the same minimum, so an older copy stops
# startup instead. These keep the use lines in step with Build.PL. #1791.

use strict; use warnings;

use Test::More 0.88;
use File::Find;

open my $fh, '<', 'Build.PL' or die "cannot read Build.PL: $!";
my $build = do { local $/; <$fh> };
close $fh;

my ($required) = $build =~ m/'SNMP::Info'\s*=>\s*'([\d.]+)'/;
ok(defined $required, 'Build.PL requires a version of SNMP::Info')
  or BAIL_OUT('no SNMP::Info requirement in Build.PL');

my %use_lines;
find({ no_chdir => 1, wanted => sub {
  return unless m/\.pm\z/ or m{^bin/};
  return unless -f $_;
  open my $in, '<', $_ or die "cannot read $_: $!";
  while (my $line = <$in>) {
    $use_lines{$_} = $line if $line =~ m/^\s*use\s+SNMP::Info\b/;
  }
  close $in;
}}, 'lib', 'bin');

subtest 'snmpInfoUse__loading_modules__found' => sub {
  ok(scalar keys %use_lines, 'some module loads SNMP::Info');
};

subtest 'snmpInfoUse__every_module__states_the_build_pl_minimum' => sub {
  foreach my $file (sort keys %use_lines) {
    like($use_lines{$file}, qr/^\s*use\s+SNMP::Info\s+\Q$required\E\s*;/,
      "$file: use SNMP::Info $required;");
  }
};

done_testing;
