#!/usr/bin/env perl

# The logic behind xt/bin/cpan-audit-coverage and cpan-audit-fix-hints, fed
# fixtures so it runs without CPAN::Audit, which only the CI audit steps install.

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::CpanAudit qw(unnamed_dists coverage_message);

my %module2dist = (
  'DBI'                       => 'DBI',
  'DBI::Const'                => 'DBI',
  'HTTP::Date'                => 'HTTP-Date',
  'Dancer::Session::Abstract' => 'Dancer',
  'App::Netdisco::Util::Web'  => 'App-Netdisco',
  'Opcode'                    => 'perl',
);

my %advisories = (
  'DBI'          => ['CPANSA-DBI-1'],
  'HTTP-Date'    => ['CPANSA-HTTP-Date-1'],
  'Dancer'       => ['CPANSA-Dancer-1'],
  'App-Netdisco' => ['CPANSA-App-Netdisco-1'],
  'perl'         => ['CPANSA-perl-1'],
);

sub unnamed {
  my %args = @_;
  return [ unnamed_dists(
    module2dist => \%module2dist,
    advisories  => \%advisories,
    ignored     => {},
    requires    => {},
    %args,
  ) ];
}

subtest 'unnamed_dists__unrequired_dist_with_advisory__reported' => sub {
  is_deeply unnamed(loaded => { 'DBI' => 'DBIx::Class::Storage::DBI' }),
    [{ dist => 'DBI', module => 'DBI', loader => 'DBIx::Class::Storage::DBI' }];
};

subtest 'unnamed_dists__required_at_zero__not_reported' => sub {
  is_deeply unnamed(loaded => { 'DBI' => 'X' }, requires => { 'DBI' => 0 }), [];
};

subtest 'unnamed_dists__other_module_of_same_dist_required__not_reported' => sub {
  is_deeply unnamed(loaded => { 'DBI::Const' => 'X' }, requires => { 'DBI' => '1.656' }), [];
};

subtest 'unnamed_dists__all_advisories_ignored__not_reported' => sub {
  is_deeply unnamed(
    loaded  => { 'Dancer::Session::Abstract' => 'Dancer' },
    ignored => { 'CPANSA-Dancer-1' => 1 },
  ), [];
};

subtest 'unnamed_dists__module_without_advisories__not_reported' => sub {
  is_deeply unnamed(loaded => { 'Try::Tiny' => 'X' }), [];
};

subtest 'unnamed_dists__netdisco_and_perl__not_reported' => sub {
  is_deeply unnamed(loaded => { 'App::Netdisco::Util::Web' => 'X', 'Opcode' => 'Y' }), [];
};

subtest 'coverage_message__finding__names_dist_loader_and_fix' => sub {
  is coverage_message({ dist => 'DBI', module => 'DBI', loader => 'DBIx::Class::Storage::DBI' }),
    join("\n",
      q{DBI has CPANSec advisories, and Netdisco loads it (through DBIx::Class::Storage::DBI), but},
      q{Build.PL does not name it, so the minimums audit cannot check the version an},
      q{existing install may have. Add 'DBI' to requires in Build.PL; the minimums},
      q{audit then reports the minimum that clears its advisories, or the advisory goes},
      q{in .cpanauditignore with the reason it does not apply.},
    ) . "\n";
};

done_testing;
