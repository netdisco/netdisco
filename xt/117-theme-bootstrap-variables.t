#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Spec::Functions qw/catfile/;

# A theme sets Bootstrap's variables by name. After a Bootstrap upgrade a
# renamed variable is set but never read, so the theme silently stops applying.

sub read_file {
  my $path = shift;
  open my $fh, '<', $path or die "cannot read $path: $!";
  local $/;
  return <$fh>;
}

sub unknown_variables {
  my ($theme_css, $bootstrap_css) = @_;
  my %set = map { $_ => 1 } ($theme_css =~ m/(--bs-[a-z0-9-]+)\s*:/g);
  return sort grep { index($bootstrap_css, "var($_") < 0
                     and index($bootstrap_css, "$_:") < 0 } keys %set;
}

my $bootstrap = read_file(catfile(qw/share public css bootstrap.min.css/));

is_deeply [ unknown_variables('x { --bs-primary: #000; --bs-no-such-thing: 1px; }', $bootstrap) ],
  [ '--bs-no-such-thing' ],
  'unknownVariables__control_with_a_made_up_variable__is_detected';

my @themes = glob catfile(qw/share public css themes *.css/);
note scalar(@themes) . ' shipped theme(s)';

foreach my $theme (@themes) {
  is_deeply [ unknown_variables(read_file($theme), $bootstrap) ], [],
    "shippedTheme__${theme}__sets_only_variables_bootstrap_defines";
}

done_testing;
