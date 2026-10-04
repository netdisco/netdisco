#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Temp ();
use File::Spec::Functions qw/catfile/;

use App::Netdisco::Web::Theme qw/find_theme_file theme_problem_message/;

sub theme_dir_with {
  my $dir = File::Temp->newdir(CLEANUP => 1);
  foreach my $name (@_) {
    open my $fh, '>', catfile("$dir", "$name.css") or die "cannot write: $!";
    print $fh "[data-bs-theme=\"$name\"] { --bs-primary: #000000; }\n";
    close $fh;
  }
  return $dir;
}

my $shipped = theme_dir_with('classic');
my $local   = theme_dir_with('classic', 'site');
my $empty   = File::Temp->newdir(CLEANUP => 1);
my $missing = catfile("$empty", 'no-such-dir');

is find_theme_file(undef, "$shipped"), undef,
  'findThemeFile__undefined_name__resolves_nothing';
is find_theme_file('', "$shipped"), undef,
  'findThemeFile__empty_name__resolves_nothing';

is find_theme_file('classic', "$shipped", "$local"), catfile("$shipped", 'classic.css'),
  'findThemeFile__name_in_both__shipped_wins_over_site_local';
is find_theme_file('site', "$shipped", "$local"), catfile("$local", 'site.css'),
  'findThemeFile__name_only_site_local__resolves_there';
is find_theme_file('absent', "$shipped", "$local"), undef,
  'findThemeFile__name_nowhere__resolves_nothing';
is find_theme_file('site', $missing, "$local"), catfile("$local", 'site.css'),
  'findThemeFile__a_missing_directory__is_skipped_not_fatal';

foreach my $bad ('../classic', 'a/classic', 'classic.css', 'clas sic', "classic\n") {
  (my $label = $bad) =~ s/\n/\\n/;
  is find_theme_file($bad, "$shipped"), undef,
    "findThemeFile__name_${label}__is_refused_not_resolved";
}

my $notfound = theme_problem_message('absent', '/a/themes', '/b/themes');
like $notfound, qr/web_theme/, 'themeProblemMessage__not_found__names_the_setting';
like $notfound, qr/absent\.css/, 'themeProblemMessage__not_found__names_the_file_looked_for';
like $notfound, qr{/a/themes, /b/themes}, 'themeProblemMessage__not_found__lists_every_place_searched';
like $notfound, qr/remove web_theme/, 'themeProblemMessage__not_found__says_how_to_return_to_the_default';

my $invalid = theme_problem_message('../x', '/a/themes');
like $invalid, qr/letters, digits/, 'themeProblemMessage__invalid_name__states_the_allowed_characters';
unlike $invalid, qr{/a/themes}, 'themeProblemMessage__invalid_name__does_not_claim_a_search_happened';

done_testing;
