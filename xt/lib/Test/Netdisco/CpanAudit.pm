package Test::Netdisco::CpanAudit;

# Logic for xt/bin/cpan-audit-coverage and xt/bin/cpan-audit-fix-hints. The
# scripts read CPAN::Audit's database and reports and pass plain data in, so
# xt/218 can test this without CPAN::Audit installed.

use strict;
use warnings;

use Exporter 'import';

use version;

our @EXPORT_OK = qw(unnamed_dists coverage_message fix_hints);

# Netdisco's own advisories are for its vendored javascript, which retire.js
# checks, and no minimum in Build.PL can upgrade a site's perl
my %not_ours = map { $_ => 1 } qw/App-Netdisco perl/;

# Each dist Netdisco loads that has an advisory not in .cpanauditignore, but
# that no runtime requirement names, with the first of its modules loaded and
# what loaded it.
sub unnamed_dists {
  my %args = @_;
  my ($module2dist, $advisories, $ignored) = @args{qw/module2dist advisories ignored/};

  my %named = map { ($module2dist->{$_} // '') => 1 } keys %{ $args{requires} };
  my %found;

  foreach my $module (sort keys %{ $args{loaded} }) {
    my $dist = $module2dist->{$module} or next;
    next if $not_ours{$dist} or $named{$dist} or $found{$dist};
    next unless grep { !$ignored->{$_} } @{ $advisories->{$dist} || [] };
    $found{$dist} = { dist => $dist, module => $module, loader => $args{loaded}->{$module} };
  }

  return map { $found{$_} } sort keys %found;
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

my $ignore_reason = "to .cpanauditignore with the reason it does not apply to Netdisco.\n";

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
      . _list(@ids) . ', or add ' . (@ids > 1 ? 'them' : 'it') . "\n$ignore_reason";
  }

  my $best;
  foreach my $bound (map { $_->[1] } @fixed) {
    $best = $bound if !$best or _beyond($bound, $best);
  }
  return "To clear this: raise $module in Build.PL $best->[0] $best->[1], or add " . _list(@ids) . "\n$ignore_reason";
}

sub _unfixed_hint {
  my ($module, @unfixed) = @_;
  return '' unless @unfixed;
  my $them = @unfixed > 1 ? 'them' : 'it';
  return 'No release fixes ' . _list(map { $_->[0] } @unfixed)
    . ", so no minimum for $module in Build.PL can clear $them:\n"
    . "add $them $ignore_reason";
}

sub _list {
  my @items = @_;
  return $items[0] if @items == 1;
  return join(', ', @items[0 .. $#items - 1]) . " and $items[-1]";
}

1;
