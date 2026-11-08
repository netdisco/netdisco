#!/usr/bin/env perl

# The logic behind xt/bin/cpan-audit-coverage and cpan-audit-fix-hints, fed
# fixtures so it runs without CPAN::Audit, which only the CI audit steps install.

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::CpanAudit qw(unnamed_dists coverage_message fix_hints);

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

# a cpan-audit --json report holding one dist
sub report {
  my ($dist, $module, @advisories) = @_;
  return { dists => { $dist => {
    queried_modules => [$module],
    version         => '>=0',
    advisories      => [ map { { id => $_->[0], fixed_versions => $_->[1] } } @advisories ],
  } } };
}

my $ignore_tail = "\nto .cpanauditignore with the reason it does not apply to Netdisco.\n";

subtest 'fix_hints__one_fixed_advisory__raise_to_fixed_version' => sub {
  is_deeply [ fix_hints(report('HTTP-Date', 'HTTP::Date', ['CPANSA-HTTP-Date-2026-14741', ['>=6.08']])) ],
    [ 'To clear this: raise HTTP::Date in Build.PL to 6.08, or add CPANSA-HTTP-Date-2026-14741' . $ignore_tail ];
};

subtest 'fix_hints__greater_than_form__says_above' => sub {
  is_deeply [ fix_hints(report('Encode', 'Encode', ['CPANSA-Encode-2021-01', ['>3.11']])) ],
    [ 'To clear this: raise Encode in Build.PL above 3.11, or add CPANSA-Encode-2021-01' . $ignore_tail ];
};

subtest 'fix_hints__several_fixed__gives_highest_and_lists_all_ids' => sub {
  is_deeply [ fix_hints(report('DBI', 'DBI',
      ['CPANSA-DBI-1', ['>=1.643']], ['CPANSA-DBI-2', ['>=1.656']])) ],
    [ 'To clear this: raise DBI in Build.PL to 1.656, or add CPANSA-DBI-1 and CPANSA-DBI-2' . $ignore_tail ];
};

my $unfixed = "No release fixes CPANSA-X-1, so no minimum for Sereal::Decoder in Build.PL can clear it:\n"
  . "add it to .cpanauditignore with the reason it does not apply to Netdisco.\n";

subtest 'fix_hints__no_fixed_release__only_ignore_entry' => sub {
  is_deeply [ fix_hints(report('Sereal-Decoder', 'Sereal::Decoder', ['CPANSA-X-1', []])) ], [ $unfixed ];
};

subtest 'fix_hints__fixed_and_unfixed_mixed__gives_highest_minimum_and_lists_unfixed' => sub {
  is_deeply [ fix_hints(report('Sereal-Decoder', 'Sereal::Decoder',
      ['CPANSA-X-1', []], ['CPANSA-X-2', ['>=5.005']])) ],
    [ 'To clear this: raise Sereal::Decoder in Build.PL to 5.005, or add CPANSA-X-2' . $ignore_tail . $unfixed ];
};

subtest 'fix_hints__unrecognized_range__points_at_fixed_range' => sub {
  is_deeply [ fix_hints(report('M', 'M', ['CPANSA-M-1', ['>=1.0,<2.0']])) ],
    [ 'To clear this: raise M in Build.PL past the Fixed range shown above for CPANSA-M-1, or add it' . $ignore_tail ];
};

done_testing;
