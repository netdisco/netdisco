package Test::Netdisco::CpanAudit;

# Logic for xt/bin/cpan-audit-coverage and xt/bin/cpan-audit-fix-hints. The
# scripts read CPAN::Audit's database and reports and pass plain data in, so
# xt/218 can test this without CPAN::Audit installed.

use strict;
use warnings;

use Exporter 'import';

use IPC::Open3;
use JSON::PP;
use version;

our @EXPORT_OK = qw(unnamed_dists coverage_message fix_hints ignored_ids read_report compile_error);

# Netdisco's own advisories are for its vendored javascript, which retire.js
# checks, and no minimum in Build.PL can upgrade a site's perl
my %not_ours = map { $_ => 1 } qw/App-Netdisco perl/;

# The ids in .cpanauditignore's lines, read as cpan-audit's --exclude-file
# reads them (CPAN::Audit::_handle_exclude_file), uppercased as its filter
# compares them, so the guard skips exactly what the audit skips.
sub ignored_ids {
  my @ids = grep { length } map { (my $line = $_) =~ s/#.*//; $line =~ s/^\s+|\s+$//g; $line } @_;
  return { map { uc($_) => 1 } @ids };
}

# Each dist Netdisco loads that has an advisory not in .cpanauditignore, but
# that no runtime requirement names, with the first of its modules loaded and
# what loaded it. Each advisory is its id followed by its CVE ids; ignoring
# any of them ignores the advisory, as in CPAN::Audit::Filter.
sub unnamed_dists {
  my %args = @_;
  my ($module2dist, $advisories, $ignored) = @args{qw/module2dist advisories ignored/};

  my %named = map { ($module2dist->{$_} // '') => 1 } keys %{ $args{requires} };
  my %found;

  foreach my $module (sort keys %{ $args{loaded} }) {
    my $dist = $module2dist->{$module} or next;
    next if $not_ours{$dist} or $named{$dist} or $found{$dist};
    next unless grep { !_is_ignored($_, $ignored) } @{ $advisories->{$dist} || [] };
    $found{$dist} = { dist => $dist, module => $module, loader => $args{loaded}->{$module} };
  }

  return map { $found{$_} } sort keys %found;
}

sub _is_ignored {
  my ($ids, $ignored) = @_;
  return scalar grep { $ignored->{ uc $_ } } @{$ids};
}

sub coverage_message {
  my $finding = shift;
  my ($dist, $module, $loader) = @{$finding}{qw/dist module loader/};

  return join "\n",
    "$dist has CPANSec advisories, and Netdisco loads it (through $loader), but",
    q{Build.PL does not name it, so the minimums audit cannot check the version an},
    qq{existing install may have. Add '$module' to requires in Build.PL; the minimums},
    q{audit then reports the minimum that clears its advisories, or the advisory goes},
    q{in .cpanauditignore with the reason it does not apply.},
    '';
}

sub _ignore_reason {
  my $count = shift;
  return "to .cpanauditignore with the reason " . ($count > 1 ? 'they do' : 'it does') . " not apply to Netdisco.\n";
}

# cpan-audit --json's stdout, decoded; empty when cpan-audit itself failed
sub read_report {
  my $text = shift;
  die "cpan-audit printed no report, so there are no hints: its own error is above.\n"
    unless defined $text and $text =~ m/\S/;
  my $report = eval { JSON::PP->new->decode($text) };
  return $report if $report;
  die "cpan-audit's --json report did not parse, so there are no hints: $@";
}

# The first line of what a command printed when it failed, or undef when it
# succeeded. The command runs without a shell, so no path needs quoting.
sub compile_error {
  my @command = @_;
  my $pid = open3(my $to_child, my $from_child, undef, @command);
  close $to_child;
  my @output = <$from_child>;
  waitpid $pid, 0;
  return undef if $? == 0;
  my $first_line = $output[0] // "exited with status $?";
  chomp $first_line;
  return $first_line;
}

# One line of advice per failing dist in a cpan-audit --json report: the
# minimum that clears its fixable advisories, and which need an ignore entry.
sub fix_hints {
  my $report = shift;
  my @hints;

  foreach my $dist (sort keys %{ $report->{dists} }) {
    my $entry = $report->{dists}->{$dist};
    my $module = $entry->{queried_modules}->[0] // $dist;
    my (@fixed, @unfixed);
    foreach my $advisory (@{ $entry->{advisories} }) {
      my $bound = _clearing_bound($advisory);
      push @{ $bound ? \@fixed : \@unfixed }, [ $advisory->{id}, $bound ];
    }
    push @hints, _raise_hint($module, @fixed) . _unfixed_hint($module, @unfixed);
  }
  return @hints;
}

my $version_re = qr/v?[0-9][0-9._]*/;

# What a minimum must reach to clear one advisory: [ 'to' or 'above', version ],
# 'unknown' for a fixed range in a form this does not read, or undef when no
# minimum clears it. The database often leaves fixed_versions empty when the
# affected range has an upper bound, which a minimum past that bound clears.
sub _clearing_bound {
  my $advisory = shift;
  my $fixed = $advisory->{fixed_versions}->[0];

  if (defined $fixed and length $fixed) {
    my ($op, $wanted) = $fixed =~ m/^\s*(>=?)\s*($version_re)\s*$/ or return 'unknown';
    return [ ($op eq '>=' ? 'to' : 'above'), $wanted ];
  }

  my $best;
  foreach my $range (@{ $advisory->{affected_versions} || [] }) {
    my $bound = _upper_bound($range) or return undef;
    $best = $bound if !$best or _beyond($bound, $best);
  }
  return $best;
}

# "<2.25" is cleared at 2.25, "<=5.001" and "==0.01" only above them
sub _upper_bound {
  my $range = shift;
  foreach my $part (split m/\s*,\s*/, $range) {
    my ($op, $version) = $part =~ m/^\s*(<=?|==)\s*($version_re)\s*$/ or next;
    return [ ($op eq '<' ? 'to' : 'above'), $version ];
  }
  return undef;
}

# whether bound $a needs a higher minimum than bound $b; at the same version,
# "above" is the stricter of the two
sub _beyond {
  my ($a, $b) = @_;
  my $order = version->parse($a->[1]) <=> version->parse($b->[1]);
  return $order > 0 || ($order == 0 && $a->[0] eq 'above' && $b->[0] eq 'to');
}

# "to 6.08" or "above 3.11"; a fixed range in any other form sends the reader
# to the range cpan-audit printed rather than guess
sub _raise_hint {
  my ($module, @fixed) = @_;
  return '' unless @fixed;
  my @ids = map { $_->[0] } @fixed;

  if (grep { !ref $_->[1] } @fixed) {
    return "To clear this: raise $module in Build.PL past the Fixed range shown above for "
      . _list(@ids) . ', or add ' . (@ids > 1 ? 'them' : 'it') . "\n" . _ignore_reason(scalar @ids);
  }

  my $best;
  foreach my $bound (map { $_->[1] } @fixed) {
    $best = $bound if !$best or _beyond($bound, $best);
  }
  return "To clear this: raise $module in Build.PL $best->[0] $best->[1], or add " . _list(@ids) . "\n" . _ignore_reason(scalar @ids);
}

sub _unfixed_hint {
  my ($module, @unfixed) = @_;
  return '' unless @unfixed;
  my $them = @unfixed > 1 ? 'them' : 'it';
  return 'No release fixes ' . _list(map { $_->[0] } @unfixed)
    . ", so no minimum for $module in Build.PL can clear $them:\n"
    . "add $them " . _ignore_reason(scalar @unfixed);
}

sub _list {
  my @items = @_;
  return $items[0] if @items == 1;
  return join(', ', @items[0 .. $#items - 1]) . " and $items[-1]";
}

1;
