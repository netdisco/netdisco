package App::Netdisco::Web::Theme;

use Dancer ':syntax';
use Path::Class qw/dir file/;

use base 'Exporter';
our @EXPORT_OK = qw/find_theme_file theme_problem_message/;

# A theme name becomes a file name, so nothing that could leave the directory.
my $VALID_NAME = qr/\A[A-Za-z0-9_-]+\z/;

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

true;
