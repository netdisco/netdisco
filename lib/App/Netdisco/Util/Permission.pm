package App::Netdisco::Util::Permission;

use strict;
use warnings;
use Dancer qw/:syntax :script/;

use Scalar::Util 'blessed';
use NetAddr::IP::Lite ':lower';
use App::Netdisco::Util::DNS 'hostname_from_ip';

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

Given a Device or IP address, compares it to the items in C<< \@config >>
then returns true or false. You can control whether any item must match or
all must match, and items can be negated to invert the match logic.

There are several options for what C<< \@config >> can contain:

=over 4

=item *

Hostname, IP address, IP prefix (subnet)

=item *

IP address range, using a hyphen on the last octet/hextet, and no whitespace

=item *

Regular expression in YAML format (no enforced anchors) which will match the
device DNS name (using a fresh DNS lookup, so works on new discovery), e.g.:

 - !!perl/regexp ^sep0.*$

=item *

"C<property:regexp>" - matched against a device property, such as C<model> or
C<vendor> (with enforced begin/end regexp anchors).

=item *

"C<op:and>" to require all items to match (or not match) the provided IP or
device. Note that this includes IP address version mismatches (v4-v6).

=back

To negate any entry, prefix it with "C<!>", for example "C<!192.0.2.0/29>". In
that case, the item must I<not> match the device. This does not apply to
regular expressions (which you can achieve with nonmatching lookahead).

To match any device, use "C<any>". To match no devices we suggest using
"C<broadcast>" in the list.

=cut

sub check_acl {
  my ($thing, $config) = @_;
  my $real_ip = (
    (blessed $thing and $thing->can('ip')) ? $thing->ip : (
      (blessed $thing and $thing->can('addr')) ? $thing->addr : $thing ));
  return 0 if blessed $real_ip; # class we do not understand

  my $addr = NetAddr::IP::Lite->new($real_ip);
  my $name = hostname_from_ip($addr->addr) || '!!NO_HOSTNAME!!';
  my $all  = (scalar grep {m/^op:and$/} @$config);

  INLIST: foreach my $item (@$config) {
      next INLIST if $item eq 'op:and';

      if (ref qr// eq ref $item) {
          if ($name =~ $item) {
            return 1 if not $all;
          }
          else {
            return 0 if $all;
          }
          next INLIST;
      }

      my $neg = ($item =~ s/^!//);

      if ($item =~ m/^([^:]+)\s*:\s*([^:]+)$/) {
          my $prop  = $1;
          my $match = $2;

          # if not in storage, we can't do much with device properties
          next INLIST unless blessed $thing and $thing->in_storage;

          # lazy version of vendor: and model:
          if ($neg xor ($thing->can($prop) and defined $thing->$prop
              and $thing->$prop =~ m/^$match$/)) {
            return 1 if not $all;
          }
          else {
            return 0 if $all;
          }
          next INLIST;
      }

      if ($item =~ m/([a-f0-9]+)-([a-f0-9]+)$/i) {
          my $first = $1;
          my $last  = $2;

          if ($item =~ m/:/) {
              next INLIST if $addr->bits != 128 and not $all;

              $first = hex $first;
              $last  = hex $last;

              (my $header = $item) =~ s/:[^:]+$/:/;
              foreach my $part ($first .. $last) {
                  my $ip = NetAddr::IP::Lite->new($header . sprintf('%x',$part) . '/128')
                    or next;
                  if ($neg xor ($ip == $addr)) {
                    return 1 if not $all;
                    next INLIST;
                  }
              }
              return 0 if (not $neg and $all);
              return 1 if ($neg and not $all);
          }
          else {
              next INLIST if $addr->bits != 32 and not $all;

              (my $header = $item) =~ s/\.[^.]+$/./;
              foreach my $part ($first .. $last) {
                  my $ip = NetAddr::IP::Lite->new($header . $part . '/32')
                    or next;
                  if ($neg xor ($ip == $addr)) {
                    return 1 if not $all;
                    next INLIST;
                  }
              }
              return 0 if (not $neg and $all);
              return 1 if ($neg and not $all);
          }
          next INLIST;
      }

      my $ip = NetAddr::IP::Lite->new($item)
        or next INLIST;
      next INLIST if $ip->bits != $addr->bits and not $all;

      if ($neg xor ($ip->contains($addr))) {
        return 1 if not $all;
      }
      else {
        return 0 if $all;
      }
      next INLIST;
  }

  return ($all ? 1 : 0);
}

1;
