#!/usr/bin/env perl

# The logic behind xt/bin/cpan-audit-coverage and cpan-audit-fix-hints, fed
# fixtures so it runs without CPAN::Audit, which only the CI audit steps install.

use strict;
use warnings;

use Test::More 0.88;
use File::Temp;
use lib 'xt/lib';
use Test::Netdisco::CpanAudit qw(unnamed_dists coverage_message fix_hints ignored_ids read_report compile_error);

my %module2dist = (
  'DBI'                       => 'DBI',
  'DBI::Const'                => 'DBI',
  'HTTP::Date'                => 'HTTP-Date',
  'Dancer::Session::Abstract' => 'Dancer',
  'App::Netdisco::Util::Web'  => 'App-Netdisco',
  'Opcode'                    => 'perl',
);

# each advisory as its id and then its CVE ids
my %advisories = (
  'DBI'          => [['CPANSA-DBI-1']],
  'HTTP-Date'    => [['CPANSA-HTTP-Date-1']],
  'Dancer'       => [['CPANSA-Dancer-1', 'CVE-2012-5572']],
  'App-Netdisco' => [['CPANSA-App-Netdisco-1']],
  'perl'         => [['CPANSA-perl-1']],
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
    ignored => ignored_ids("CPANSA-Dancer-1\n"),
  ), [];
};

subtest 'unnamed_dists__advisory_ignored_by_its_cve__not_reported' => sub {
  is_deeply unnamed(
    loaded  => { 'Dancer::Session::Abstract' => 'Dancer' },
    ignored => ignored_ids("CVE-2012-5572\n"),
  ), [];
};

subtest 'unnamed_dists__ignore_entry_in_lower_case__not_reported' => sub {
  is_deeply unnamed(
    loaded  => { 'Dancer::Session::Abstract' => 'Dancer' },
    ignored => ignored_ids("cpansa-dancer-1\n"),
  ), [];
};

# the same reading as cpan-audit's --exclude-file (CPAN::Audit::_handle_exclude_file)
subtest 'ignored_ids__comments_indentation_and_blank_lines__as_cpan_audit_reads_them' => sub {
  is_deeply ignored_ids(
    "# Does not apply: a comment line\n",
    "  CPANSA-X-1  # indented, with a trailing comment\n",
    "\n",
    "   \n",
    "cve-2020-1\n",
  ), { 'CPANSA-X-1' => 1, 'CVE-2020-1' => 1 };
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
    advisories      => [ map {
      { id => $_->[0], fixed_versions => $_->[1], affected_versions => $_->[2] || ['>0'] }
    } @advisories ],
  } } };
}

my $ignore_tail = "\nto .cpanauditignore with the reason it does not apply to Netdisco.\n";
my $ignore_tail_several = "\nto .cpanauditignore with the reason they do not apply to Netdisco.\n";

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
    [ 'To clear this: raise DBI in Build.PL to 1.656, or add CPANSA-DBI-1 and CPANSA-DBI-2' . $ignore_tail_several ];
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

# the database leaves fixed_versions empty on many advisories whose affected
# range has an upper bound, and a minimum past that bound clears them
subtest 'fix_hints__no_fixed_range_but_bounded_affected__raise_past_bound' => sub {
  is_deeply [ fix_hints(report('Digest-MD5', 'Digest::MD5', ['CPANSA-Digest-MD5-2002-0703', [], ['<2.25']])) ],
    [ 'To clear this: raise Digest::MD5 in Build.PL to 2.25, or add CPANSA-Digest-MD5-2002-0703' . $ignore_tail ];
};

subtest 'fix_hints__no_fixed_range_inclusive_bound__says_above' => sub {
  is_deeply [ fix_hints(report('Sereal-Encoder', 'Sereal::Encoder',
      ['CPANSA-Sereal-Encoder-2021-24032-zstd', [], ['>=4.019,<=5.001']])) ],
    [ 'To clear this: raise Sereal::Encoder in Build.PL above 5.001, or add CPANSA-Sereal-Encoder-2021-24032-zstd' . $ignore_tail ];
};

subtest 'fix_hints__no_fixed_range_unbounded_affected__only_ignore_entry' => sub {
  is_deeply [ fix_hints(report('Sereal-Decoder', 'Sereal::Decoder', ['CPANSA-X-1', [], ['>=5.002_001']])) ],
    [ $unfixed ];
};

subtest 'fix_hints__same_version_at_and_above__says_above' => sub {
  is_deeply [ fix_hints(report('D', 'D', ['CPANSA-D-1', ['>=1.0']], ['CPANSA-D-2', ['>1.0']])) ],
    [ 'To clear this: raise D in Build.PL above 1.0, or add CPANSA-D-1 and CPANSA-D-2' . $ignore_tail_several ];
};

subtest 'fix_hints__unrecognized_range__points_at_fixed_range' => sub {
  is_deeply [ fix_hints(report('M', 'M', ['CPANSA-M-1', ['>=1.0,<2.0']])) ],
    [ 'To clear this: raise M in Build.PL past the Fixed range shown above for CPANSA-M-1, or add it' . $ignore_tail ];
};

subtest 'fix_hints__several_unfixed__says_they' => sub {
  is_deeply [ fix_hints(report('S', 'S', ['CPANSA-S-1', []], ['CPANSA-S-2', []])) ],
    [ "No release fixes CPANSA-S-1 and CPANSA-S-2, so no minimum for S in Build.PL can clear them:\n"
      . "add them to .cpanauditignore with the reason they do not apply to Netdisco.\n" ];
};

subtest 'read_report__json__decoded' => sub {
  is_deeply read_report('{"dists":{}}'), { dists => {} };
};

# cpan-audit prints nothing on stdout when it fails, and its own error is
# what the reader needs, not a JSON parser's complaint
subtest 'read_report__empty_output__says_cpan_audit_failed' => sub {
  eval { read_report("  \n") };
  like $@, qr/^cpan-audit printed no report, so there are no hints: its own error is above\.$/;
};

subtest 'read_report__not_json__names_the_report_and_the_parse_error' => sub {
  eval { read_report('Usage: cpan-audit') };
  like $@, qr/^cpan-audit's --json report did not parse, so there are no hints: /;
};

my $scripts = File::Temp->newdir;
my $spaced_dir = $scripts->dirname . '/with space';
mkdir $spaced_dir or die "cannot make $spaced_dir: $!";

sub script {
  my ($name, $body) = @_;
  my $path = "$spaced_dir/$name";
  open my $out, '>', $path or die "cannot write $path: $!";
  print {$out} $body;
  close $out;
  return $path;
}

subtest 'compile_error__compiles_in_a_path_with_a_space__undef' => sub {
  is compile_error($^X, '-c', script('ok.pl', "print qq(at compile time\n) if 0;\n")), undef;
};

subtest 'compile_error__fails_to_compile__first_line_of_the_error' => sub {
  like compile_error($^X, '-c', script('bad.pl', "use No::Such::Module::Here;\n")),
    qr/^Can't locate No\/Such\/Module\/Here\.pm in \@INC/;
};

# a failed require leaves an undef entry in %INC; the recorder must neither
# warn on it nor record the module as loaded
subtest 'load_recorder__failed_require__not_recorded_and_no_warning' => sub {
  my $record = File::Temp->new;
  local $ENV{LOAD_RECORD} = $record->filename;
  my $broken = script('Broken.pm', "package Broken; die qq(broken\n);\n");
  my $output = `"$^X" -Ixt/lib "-I$spaced_dir" -MTest::Netdisco::LoadRecorder -e "eval { require Broken }; require Text::Wrap" 2>&1`;
  is $output, '', 'nothing printed';
  open my $lines, '<', $record->filename or die "cannot read the record: $!";
  my %loaded = map { (split /\t/)[0] => 1 } <$lines>;
  ok $loaded{'Text::Wrap'}, 'a module that loaded is recorded';
  ok !$loaded{'Broken'}, 'the module that failed is not';
};

done_testing;
