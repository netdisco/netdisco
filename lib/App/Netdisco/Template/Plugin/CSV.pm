package App::Netdisco::Template::Plugin::CSV;

use strict;
use warnings;

use base 'Template::Plugin::CSV';

=head1 NAME

App::Netdisco::Template::Plugin::CSV

=head1 DESCRIPTION

Registered in place of L<Template::Plugin::CSV> as the C<csv> plugin (see
C<engines.netdisco_template_toolkit.PLUGINS> in F<share/config.yml>), so
every C<*_csv.tt> template's C<[% USE CSV %]> picks this up with no
per-template change. A cell whose first character is C<=>, C<+>, C<->,
C<@> or a tab is prefixed with a single quote before
being written, unless the whole cell is already a plain number with an
optional leading minus sign. Line feeds and carriage returns at either end of
a cell are removed first, and each run of them inside it is written as a
single space, so every row stays on one line.

=cut

# A leading plus is deliberately not exempted.
my $VALID_NUMBER = qr/\A-?[0-9]+(?:\.[0-9]+)?\z/;

sub _neutralize {
  my $value = shift;
  return $value if !defined($value) || $value =~ $VALID_NUMBER;
  return $value =~ m/\A[=+\-\@\t\r]/ ? ("'" . $value) : $value;
}

# Text::CSV without binary refuses a control character by dropping the whole
# row, and line breaks are the ones real values carry.
sub _flatten {
  my $value = shift;
  return $value if !defined($value);
  # Trimmed rather than spaced at the ends, so a leading break cannot put a
  # space in front of a formula trigger and hide it from _neutralize.
  $value =~ s/\A[\r\n]+//;
  $value =~ s/[\r\n]+\z//;
  $value =~ s/[\r\n]+/ /g;
  return $value;
}

sub dump {
  my ($self, $array) = @_;
  $self->{csv}->combine(map { _neutralize(_flatten($_)) } @$array);
  return $self->{csv}->string;
}

sub dump_values {
  my ($self, $h) = @_;
  $self->{csv}->combine(map { _neutralize(_flatten($_)) } values %$h);
  return $self->{csv}->string;
}

1;
