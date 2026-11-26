#!/usr/bin/env perl

# Build.PL's SNMP::Info minimum is enforced only by installers. A checkout,
# an operating system package or a stray copy in site Perl gave Netdisco an
# older SNMP::Info without anyone noticing, and features that need a newer
# one, such as incomplete walk protection, turned off quietly. The minimum is
# now set once, on Util::SNMP's use line, so an older copy stops startup, and
# Build.PL reads its requirement from that line. Every other module that
# loads SNMP::Info compiles Util::SNMP first, so it is checked too. #1791.

use strict; use warnings;

use Test::More 0.88;
use File::Find;
use File::Temp 'tempdir';
use File::Spec::Functions qw/catfile rel2abs/;
use Cwd 'getcwd';
use CPAN::Meta;

my $util_snmp = 'lib/App/Netdisco/Util/SNMP.pm';

sub slurp {
  my $file = shift;
  open my $in, '<', $file or die "cannot read $file: $!";
  local $/;
  return scalar <$in>;
}

# runs Build.PL in a copy of the tree whose Util::SNMP use line is $use_line
sub build_pl_with {
  my $use_line = shift;
  my $dir = tempdir(CLEANUP => 1);
  system('cp', '-R', 'lib', 'Build.PL', $dir) == 0
    or die "cannot copy lib and Build.PL to $dir\n";
  symlink(rel2abs($_), catfile($dir, $_)) or die "cannot link $_: $!\n"
    for qw/bin share/;

  my $copy = catfile($dir, $util_snmp);
  my $source = slurp($copy);
  $source =~ s/^use\s+SNMP::Info\b[^;]*;/$use_line/m
    or die "no use SNMP::Info line in $util_snmp\n";
  open my $out, '>', $copy or die "cannot write $copy: $!";
  print $out $source;
  close $out;

  my $cwd = getcwd();
  chdir $dir or die "cannot chdir to $dir: $!";
  my $output = qx{"$^X" Build.PL 2>&1};
  my $status = $?;
  my $meta = -e 'MYMETA.json' ? CPAN::Meta->load_file('MYMETA.json') : undef;
  chdir $cwd or die "cannot chdir back to $cwd: $!";
  return ($status, $output, $meta);
}

subtest 'buildPl__util_snmp_states_a_minimum__requires_that_version' => sub {
  my ($status, $output, $meta) = build_pl_with('use SNMP::Info 3.999999;');
  is($status, 0, 'Build.PL succeeds') or diag $output;
  my $requires = $meta && $meta->effective_prereqs
    ->requirements_for('runtime', 'requires')->as_string_hash;
  is($requires && $requires->{'SNMP::Info'}, '3.999999',
    'MYMETA.json requires the version on the use line');
};

subtest 'buildPl__util_snmp_states_no_minimum__stops_naming_the_file' => sub {
  my ($status, $output) = build_pl_with('use SNMP::Info;');
  isnt($status, 0, 'Build.PL fails');
  like($output, qr/\Q$util_snmp\E/, 'the message names Util::SNMP');
};

my %loaders;
find({ no_chdir => 1, wanted => sub {
  return unless m/\.pm\z/ or m{^bin/};
  return unless -f $_ and $_ ne $util_snmp;
  my $source = slurp($_);
  $loaders{$_} = $source if $source =~ m/^\s*use\s+SNMP::Info\b/m;
}}, 'lib', 'bin');

subtest 'snmpInfoUse__other_modules__found' => sub {
  ok(scalar keys %loaders, 'some module besides Util::SNMP loads SNMP::Info');
};

subtest 'snmpInfoUse__other_modules__load_util_snmp_first_and_state_no_version' => sub {
  foreach my $file (sort keys %loaders) {
    my $source = $loaders{$file};
    $source =~ m/^\s*use\s+SNMP::Info\b/m;
    my $snmp_info_at = $-[0];
    my $util_at = $source =~ m/^\s*use\s+App::Netdisco::Util::SNMP\b/m
      ? $-[0] : undef;
    ok(defined $util_at && $util_at < $snmp_info_at,
      "$file: uses App::Netdisco::Util::SNMP before SNMP::Info");
    like($source, qr/^\s*use\s+SNMP::Info\s*;/m,
      "$file: use SNMP::Info; states no version, Util::SNMP sets it");
  }
};

done_testing;
