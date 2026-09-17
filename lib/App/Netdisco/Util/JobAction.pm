package App::Netdisco::Util::JobAction;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  action_is_refused
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::JobAction

=head1 DESCRIPTION

Job actions which the web frontend and the API will not queue.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 action_is_refused( $action )

Returns true if C<$action> names a worker intended to be run only with
C<netdisco-do> on the backend host, where the caller already holds the
privilege queueing it would otherwise confer.

=cut

my %refused_action = map {($_ => 1)} qw/
  hook scheduler psql getapikey dumpconfig dumpinfocache show
/;

# the backend keys its workers on the lowercased action ahead of the
# namespace, so the same shape decides what is refused
sub action_is_refused {
  my ($base) = split m/::/, lc(shift || '');
  return (($base and exists $refused_action{$base}) ? 1 : 0);
}

1;
