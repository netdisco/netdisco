package App::Netdisco::Web::Theme;

use Dancer ':syntax';
use Path::Class qw/dir file/;
use App::Netdisco::Util::SiteLocal 'site_local_paths';

use base 'Exporter';
our @EXPORT_OK = qw/find_theme_file theme_problem_message theme_scope_message theme_sheet_name/;

# A theme name becomes a file name, so nothing that could leave the directory.
my $VALID_NAME = qr/\A[A-Za-z0-9_-]+\z/;

# auto follows the browser's color scheme: it serves the dark sheet, whose
# rules apply only once the page's resolver sets data-bs-theme="dark".
my %SHEET_FOR = (auto => 'dark');

sub theme_sheet_name {
  my $name = shift;
  return $SHEET_FOR{$name} || $name;
}

sub find_theme_file {
  my ($name, @dirs) = @_;
  return undef unless defined $name and $name =~ $VALID_NAME;

  foreach my $dir (@dirs) {
    my $candidate = file($dir, "$name.css");
    return $candidate->stringify if -f $candidate;
  }
  return undef;
}

sub theme_problem_message {
  my ($name, @dirs) = @_;

  return sprintf q{web_theme '%s' is not a valid theme name. Use letters, digits, }
    . q{'-' and '_' only, or remove web_theme to use the default palette.}, $name
    unless $name =~ $VALID_NAME;

  return sprintf q{web_theme is '%s' but no %s.css was found in %s. Add the file }
    . q{to one of those directories, or remove web_theme to use the default palette.},
    $name, $name, join(', ', @dirs);
}

sub theme_scope_message {
  my ($name, $path, $css) = @_;
  return undef if $css =~ m/\[\s*data-bs-theme\s*=\s*(["']?)\Q$name\E\1\s*\]/;

  return sprintf q{web_theme '%s' was loaded from %s, but none of its rules are }
    . q{scoped to [data-bs-theme="%s"], so Bootstrap will not apply them. Scope }
    . q{the rules to that selector, or set web_theme to the name the file uses.},
    $name, $path, $name;
}

sub theme_dirs {
  return (
    dir(setting('public'), 'css', 'themes')->stringify,
    map { dir($_, 'themes')->stringify } site_local_paths(),
  );
}

sub resolve_configured_theme {
  setting('_web_theme' => undef);
  my $name = setting('web_theme');
  return unless defined $name and length $name;

  my $sheet = theme_sheet_name($name);
  my @dirs = theme_dirs();
  my $path = find_theme_file($sheet, @dirs);
  return warning theme_problem_message($name, @dirs) unless $path;

  my $css = scalar file($path)->slurp;
  my $scope = theme_scope_message($sheet, $path, $css);
  warning $scope if $scope;

  setting('_web_theme' => {
    name       => $name,
    path       => $path,
    mtime      => (stat $path)[9],
  });
}

get '/theme.css' => sub {
  my $theme = setting('_web_theme');
  # No error page: this route needs no login, and with show_errors set an
  # error page lists the application's settings.
  unless ($theme and -f $theme->{path}) {
    status 'not_found';
    return '';
  }
  send_file $theme->{path}, system_path => 1, content_type => 'text/css';
};

true;
