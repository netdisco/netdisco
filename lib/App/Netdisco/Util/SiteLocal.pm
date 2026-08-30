package App::Netdisco::Util::SiteLocal;

use strict;
use warnings;

use File::Find ();

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ scan_site_local site_local_rules /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SiteLocal - find site-local files broken by shipped changes

=head1 DESCRIPTION

Site-local templates override shipped ones by relative path, so they keep
calling APIs that later releases removed. Two of the three removals below fail
silently in the browser, which is why this exists: nothing else reports them.

Detection only. This module never writes to a file and never logs.

=cut

# One row per shipped removal. A later rung adds a row here and nothing else.
#
# `pattern` is matched against each line of each file under the scanned paths.
# `release` is the release that removed the thing, for the report to cite.
my @RULES = (
  {
    name    => 'he-js',
    release => '2.105002',
    pattern => qr/\bhe\s*\.\s*(?:encode|decode)\s*\(/,
    advice  => 'he.js was removed. Use DataTable.util.escapeHtml(), which is '
             . 'loaded on every page already.',
  },
  {
    name    => 'history-js',
    release => '2.105004',
    # History with a capital H is history.js. The browser's own object is
    # lowercase, so the case distinction is the whole test. window.History
    # still exists after the removal, as the DOM interface constructor, so a
    # site's `window.History && ...` guard stops running its branch and never
    # throws. That silence is why this rule matters more than it looks.
    pattern => qr/\bHistory\s*\.\s*(?:pushState|replaceState|getState|Adapter|enabled|log)\b/,
    advice  => 'history.js was removed. Use the browser\'s own '
             . 'history.pushState() and a popstate listener.',
  },
  {
    name    => 'natural-js',
    release => '2.105004',
    # Both the registered sort-type names and the two ways a DataTables column
    # asks for one. A column asking for a type nothing registers falls back to
    # string sorting, so the rows are quietly in the wrong order.
    pattern => qr/natural-(?:asc|desc)\b|(?:"type"|'type'|sType)\s*:\s*["']natural["']/,
    advice  => 'natural.js was removed. Use a built-in DataTables type, or '
             . 'the portsort or versionsort plug-ins netdisco still ships.',
  },
);

=head2 site_local_rules

Returns the rule table as a list of hashrefs with keys C<name>, C<release> and
C<advice>. Lists what is checked without scanning anything.

=cut

sub site_local_rules {
  return map {; +{ name => $_->{name}, release => $_->{release},
                   advice => $_->{advice} } } @RULES;
}

=head2 scan_site_local( \%args )

Scans every file under each directory in C<< $args{paths} >> and returns the
findings, sorted by path then line. C<< $args{rules} >> optionally restricts the
scan to the named rules.

A finding is a hashref with keys C<path>, C<line>, C<rule>, C<release>,
C<excerpt> and C<advice>.

A directory that does not exist is skipped rather than fatal: C<template_paths>
routinely names directories a given install has not created.

=cut

sub scan_site_local {
  my $args = shift || {};
  my @paths = @{ $args->{paths} || [] };

  my %wanted = map {($_ => 1)} @{ $args->{rules} || [] };
  my @rules = (keys %wanted)
    ? (grep { $wanted{ $_->{name} } } @RULES) : @RULES;
  return () unless scalar @rules;

  my @findings = ();
  foreach my $path (@paths) {
      next unless defined $path and length $path and -d $path;
      File::Find::find({ no_chdir => 1, wanted => sub {
          return unless -f $File::Find::name;
          push @findings, _scan_file($File::Find::name, \@rules);
      }}, $path);
  }

  return sort { $a->{path} cmp $b->{path} or $a->{line} <=> $b->{line} }
         @findings;
}

# Read once, test every rule against every line. A line can match more than one
# rule and each match is its own finding, because each carries its own advice.
# The line number is counted here rather than read from $., which is not reset
# between files and would number the second file from where the first ended.
sub _scan_file {
  my ($file, $rules) = @_;

  open my $fh, '<', $file or return ();
  my @findings = ();
  my $lineno = 0;

  while (my $line = <$fh>) {
      $lineno++;
      chomp $line;
      foreach my $rule (@$rules) {
          next unless $line =~ $rule->{pattern};
          my $excerpt = $line;
          $excerpt =~ s/^\s+|\s+$//g;
          push @findings, {
            path    => $file,
            line    => $lineno,
            rule    => $rule->{name},
            release => $rule->{release},
            excerpt => $excerpt,
            advice  => $rule->{advice},
          };
      }
  }
  close $fh;

  return @findings;
}

1;
