#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use lib 'xt/lib';
use Test::Netdisco::CssRules qw/read_text css_rules/;

# The default palette follows Bootstrap, so a token classic does not set
# quietly takes a Bootstrap color in classic too.
sub uncovered {
  my ($netdisco, $classic) = @_;
  my %set = map { $_->{property} => 1 }
    grep { $_->{selector} eq '[data-bs-theme="classic"]' and $_->{property} =~ /^--nd-/ }
    css_rules($classic);
  return sort grep { !$set{$_} } map { $_->{property} }
    grep { $_->{selector} eq ':root' and $_->{property} =~ /^--nd-/ }
    css_rules($netdisco);
}

is_deeply [ uncovered(':root { --nd-a: red; --nd-b: blue; }',
                      '[data-bs-theme="classic"] { --nd-a: red; }') ],
  [ '--nd-b' ], 'uncovered__control_missing_one__reports_it';
is_deeply [ uncovered(':root { --nd-a: red; }',
                      '[data-bs-theme="classic"] .x { --nd-a: red; }') ],
  [ '--nd-a' ], 'uncovered__control_set_on_a_descendant__does_not_count';

my $netdisco = read_text('share/public/css/netdisco.css');
my $classic  = read_text('share/public/css/themes/classic.css');
ok scalar(grep { $_->{selector} eq ':root' and $_->{property} =~ /^--nd-/ } css_rules($netdisco)),
  'classicCoverage__token_block__was_found';
is_deeply [ uncovered($netdisco, $classic) ], [],
  'classicTheme__every_netdisco_token__has_a_classic_value';

done_testing;
