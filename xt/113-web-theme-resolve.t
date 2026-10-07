#!/usr/bin/env perl

use strict;
use warnings;

use Test::More 0.88;
use File::Temp ();
use File::Spec::Functions qw/catfile/;

use App::Netdisco::Web::Theme qw/find_theme_file theme_problem_message theme_scope_message theme_sheet_name/;

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

# A file found by name can still be scoped to a different name, and then
# Bootstrap never applies its rules.
is theme_scope_message('classic', '/t/classic.css', '[data-bs-theme="classic"] { --bs-primary: #000; }'),
  undef, 'themeScopeMessage__rules_scoped_to_the_name__finds_nothing_to_report';
is theme_scope_message('classic', '/t/classic.css', "[data-bs-theme='classic'] .x { color: red; }"),
  undef, 'themeScopeMessage__single_quoted_selector__is_accepted';
is theme_scope_message('classic', '/t/classic.css', '[data-bs-theme=classic] { color: red; }'),
  undef, 'themeScopeMessage__unquoted_selector__is_accepted';

my $other = theme_scope_message('classic', '/t/classic.css', '[data-bs-theme="blue"] { --bs-primary: #000; }');
like $other, qr/web_theme 'classic'/, 'themeScopeMessage__other_name__names_the_setting';
like $other, qr{/t/classic\.css}, 'themeScopeMessage__other_name__names_the_file';
like $other, qr/\[data-bs-theme="classic"\]/, 'themeScopeMessage__other_name__shows_the_selector_to_use';
isnt theme_scope_message('classic', '/t/classic.css', '[data-bs-theme="classicx"] { }'), undef,
  'themeScopeMessage__name_as_a_prefix_of_another__is_not_mistaken_for_it';

# The tests above pass their own directories, so this pins where shipped themes
# are looked for, and that they are looked for before any site-local one.
Dancer::Config::setting('public' => '/xt/public');
Dancer::Config::setting('template_paths' => ['/xt/site']);
Dancer::Config::setting('site_local_files' => 0);
is_deeply [ App::Netdisco::Web::Theme::theme_dirs() ],
  [ '/xt/public/css/themes', '/xt/site/themes' ],
  'themeDirs__shipped_and_site_local__searches_shipped_themes_first';

# auto follows the browser's color scheme, so it serves the dark sheet and the
# page decides when that sheet applies.
is theme_sheet_name('auto'), 'dark', 'themeSheetName__auto__is_the_dark_sheet';
is theme_sheet_name('classic'), 'classic', 'themeSheetName__any_other_name__is_itself';

done_testing;
