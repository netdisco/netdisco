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
      my $range = $advisory->{fixed_versions}->[0];
      push @{ defined $range && length $range ? \@fixed : \@unfixed }, [ $advisory->{id}, $range ];
    }
    push @hints, _raise_hint($module, @fixed) . _unfixed_hint($module, @unfixed);
  }
  return @hints;
}

# ">=6.08" means "to 6.08" and ">3.11" means "above 3.11"; any other form
# sends the reader to the range cpan-audit printed rather than guess.
sub _raise_hint {
  my ($module, @fixed) = @_;
  return '' unless @fixed;
  my @ids = map { $_->[0] } @fixed;
  my ($best, $how);

  foreach my $range (map { $_->[1] } @fixed) {
    my ($op, $wanted) = $range =~ m/^\s*(>=?)\s*v?([0-9][0-9._]*)\s*$/
      or return "To clear this: raise $module in Build.PL past the Fixed range shown above for "
        . _list(@ids) . ', or add ' . (@ids > 1 ? 'them' : 'it') . "\n$ignore_reason";
    next if defined $best and version->parse($wanted) <= version->parse($best);
    ($best, $how) = ($wanted, $op eq '>=' ? 'to' : 'above');
  }

  return "To clear this: raise $module in Build.PL $how $best, or add " . _list(@ids) . "\n$ignore_reason";
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
