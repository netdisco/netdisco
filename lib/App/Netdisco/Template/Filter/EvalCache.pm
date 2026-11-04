package App::Netdisco::Template::Filter::EvalCache;

use strict;
use warnings;

=head1 NAME

App::Netdisco::Template::Filter::EvalCache

=head1 DESCRIPTION

The C<evaltt_cached> filter (see C<FILTERS> in L<App::Netdisco::Web>): like
C<evaltt>, but each distinct text is compiled once and kept, up to C<$LIMIT>
texts, then dropped together. The Ports tab evaluates every external link's
URL for every port.

=cut

our $LIMIT = 500;
my %compiled = ();

sub factory {
  my $context = shift;

  return sub {
    my $text = shift;
    my $template = $compiled{$text};

    if (not $template) {
        $template = $context->template(\$text);
        %compiled = () if scalar keys %compiled >= $LIMIT;
        $compiled{$text} = $template;
    }

    return $context->process($template);
  };
}

# how many texts are held, for xt
sub _held { return scalar keys %compiled }

1;
