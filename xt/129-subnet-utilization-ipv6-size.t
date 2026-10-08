#!/usr/bin/env perl

# Checks that Subnet Utilization sizes a subnet by its address family, 32 bits
# for IPv4 and 128 for IPv6, and that the report renders an IPv6 size as a power
# of two. CI has no database (see xt/35), so the view is checked as SQL text and
# the template is rendered with sample rows.

use strict;
use warnings;

use Test::More 0.88;

my $FILE = 'lib/App/Netdisco/DB/Result/Virtual/SubnetUtilization.pm';

my $sql = do {
  open my $fh, '<', $FILE or die "$FILE: $!";
  local $/;
  my $src = <$fh>;
  close $fh;
  ($src =~ /<<'ENDSQL'\);\n(.*?)\nENDSQL/s)[0] // '';
};

ok(length $sql, 'found the view definition');

my @power_lines = grep { /power\(\s*2\s*,/ } split /\n/, $sql;

subtest 'subnet_utilization_view__size_expression__depends_on_address_family' => sub {
  is(scalar @power_lines, 2, 'the size and the percentage each compute a power of two');
  is(scalar(grep { !/family\(net\)/ } @power_lines), 0, 'each picks its bit width by address family');
  is(scalar(grep { !/WHEN 4 THEN 32 ELSE 128/ } @power_lines), 0, 'IPv4 uses 32 bits and IPv6 128');
};

subtest 'subnet_utilization_view__size_expression__never_hardcodes_32_alone' => sub {
  unlike($sql, qr/power\(\s*2\s*,\s*\(\s*32\s*-/, 'no exponent built from a bare 32');
};

subtest 'subnets_template__ipv6_row__renders_size_as_power_of_two' => sub {
  # format_number cannot format 2^64, so an IPv6 size must bypass it
  require Template;
  my $tt = Template->new({ ABSOLUTE => 1, FILTERS => { none => sub { $_[0] } } });
  my $out = '';
  my $ok = $tt->process('share/views/ajax/report/subnets.tt', {
    uri_for  => sub { '/report/ipinventory' },
    params   => {},
    settings => { thousands_separator => ',' },
    results  => [
      { subnet => '2001:db8:1::/64', subnet_size => 2**64, active => 3, percent => 0 },
      { subnet => '10.0.0.0/24',     subnet_size => 256,   active => 5, percent => 2 },
    ],
  }, \$out);
  ok($ok, 'the template renders') or diag $tt->error;
  like($out, qr{>2<sup>64</sup><}, 'the IPv6 /64 size reads as 2^64');
  like($out, qr{>256<}, 'the IPv4 /24 size still goes through format_number');
};

done_testing;
