package App::Netdisco::Util::Permission;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use Scalar::Util 'blessed';
use NetAddr::IP::Lite ':lower';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/check_acl/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Permission

=head1 DESCRIPTION

Helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 check_acl( $ip, \@config )

Given an IP address, returns true if any of the items in C<< \@config >>
matches that address, otherwise returns false.

Normally you use C<check_no> and C<check_only>, passing the name of the
configuration setting to load. This helper instead requires not the name of
the setting, but its value.

=cut

sub check_acl {
  my ($thing, $config) = @_;
  my $real_ip = (blessed $thing ? $thing->ip : $thing);
  my $addr = NetAddr::IP::Lite->new($real_ip);

  foreach my $item (@$config) {
      if (ref qr// eq ref $item) {
          my $name = hostname_from_ip($addr->addr) or next;
          return 1 if $name =~ $item;
          next;
      }

      if ($item =~ m/^([^:]+)\s*:\s*([^:]+)$/) {
          my $prop  = $1;
          my $match = $2;

          # if not in storage, we can't do much with device properties
          next unless blessed $thing and $thing->in_storage;

          # lazy version of vendor: and model:
          if ($thing->can($prop) and defined $thing->$prop
              and $thing->$prop =~ m/^$match$/) {
              return 1;
          }

          next;
      }

      if ($item =~ m/([a-f0-9]+)-([a-f0-9]+)$/i) {
          my $first = $1;
          my $last  = $2;

          if ($item =~ m/:/) {
              next unless $addr->bits == 128;

              $first = hex $first;
              $last  = hex $last;

              (my $header = $item) =~ s/:[^:]+$/:/;
              foreach my $part ($first .. $last) {
                  my $ip = NetAddr::IP::Lite->new($header . sprintf('%x',$part) . '/128')
                    or next;
                  return 1 if $ip == $addr;
              }
          }
          else {
              next unless $addr->bits == 32;

              (my $header = $item) =~ s/\.[^.]+$/./;
              foreach my $part ($first .. $last) {
                  my $ip = NetAddr::IP::Lite->new($header . $part . '/32')
                    or next;
                  return 1 if $ip == $addr;
              }
          }

          next;
      }

      my $ip = NetAddr::IP::Lite->new($item)
        or next;
      next unless $ip->bits == $addr->bits;

      return 1 if $ip->contains($addr);
  }

  return 0;
}

1;
