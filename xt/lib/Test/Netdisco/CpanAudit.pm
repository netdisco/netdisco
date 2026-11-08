package Test::Netdisco::CpanAudit;

# Logic for xt/bin/cpan-audit-coverage and xt/bin/cpan-audit-fix-hints. The
# scripts read CPAN::Audit's database and reports and pass plain data in, so
# xt/218 can test this without CPAN::Audit installed.

use strict;
use warnings;

use Exporter 'import';

our @EXPORT_OK = qw(unnamed_dists coverage_message);

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

1;
