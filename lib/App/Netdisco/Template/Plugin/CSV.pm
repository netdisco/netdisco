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
C<@>, a tab or a carriage return is prefixed with a single quote before
being written, unless the whole cell is already a plain number with an
optional leading minus sign.

=cut

# A leading plus is deliberately not exempted.
my $VALID_NUMBER = qr/\A-?[0-9]+(?:\.[0-9]+)?\z/;

sub _neutralize {
  my $value = shift;
  return $value if !defined($value) || $value =~ $VALID_NUMBER;
  return $value =~ m/\A[=+\-\@\t\r]/ ? ("'" . $value) : $value;
}

sub dump {
  my ($self, $array) = @_;
  $self->{csv}->combine(map { _neutralize($_) } @$array);
  return $self->{csv}->string;
}

sub dump_values {
  my ($self, $h) = @_;
  $self->{csv}->combine(map { _neutralize($_) } values %$h);
  return $self->{csv}->string;
}

1;
