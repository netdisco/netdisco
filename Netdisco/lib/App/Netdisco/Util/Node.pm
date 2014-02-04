package App::Netdisco::Util::Node;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use NetAddr::IP::Lite ':lower';
use App::Netdisco::Util::DNS 'hostname_from_ip';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  check_node_acl
  check_node_no
  check_node_only
  is_nbtstatable
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Node

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 check_node_acl( $ip, \@config )

Given the IP address of a node, returns true if any of the items in C<<
\@config >> matches that node, otherwise returns false.

Normally you use C<check_node_no> and C<check_node_only>, passing the name of the
configuration setting to load. This helper instead requires not the name of
the setting, but its value.

=cut

sub check_node_acl {
  my ($ip, $config) = @_;
  my $device = get_device($ip) or return 0;
  my $addr = NetAddr::IP::Lite->new($device->ip);

  foreach my $item (@$config) {
      if (ref qr// eq ref $item) {
          my $name = hostname_from_ip($addr->addr) or next;
          return 1 if $name =~ $item;
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

=head2 check_node_no( $ip, $setting_name )

Given the IP address of a node, returns true if the configuration setting
C<$setting_name> matches that device, else returns false. If the setting
is undefined or empty, then C<check_node_no> also returns false.

 print "rejected!" if check_node_no($ip, 'nbtstat_no');

There are several options for what C<$setting_name> can contain:

=over 4

=item *

Hostname, IP address, IP prefix

=item *

IP address range, using a hyphen and no whitespace

=item *

Regular Expression in YAML format which will match the node DNS name, e.g.:

 - !!perl/regexp ^sep0.*$

=back

To simply match all nodes, use "C<any>" or IP Prefix "C<0.0.0.0/0>". All
regular expressions are anchored (that is, they must match the whole string).
To match no nodes we recommend an entry of "C<localhost>" in the setting.

=cut

sub check_node_no {
  my ($ip, $setting_name) = @_;

  my $config = setting($setting_name) || [];
  return 0 if not scalar @$config;

  return check_acl($ip, $config);
}

=head2 check_node_only( $ip, $setting_name )

Given the IP address of a node, returns true if the configuration setting
C<$setting_name> matches that node, else returns false. If the setting
is undefined or empty, then C<check_node_only> also returns true.

 print "rejected!" unless check_node_only($ip, 'nbtstat_only');

There are several options for what C<$setting_name> can contain:

=over 4

=item *

Hostname, IP address, IP prefix

=item *

IP address range, using a hyphen and no whitespace

=item *

Regular Expression in YAML format which will match the node DNS name, e.g.:

 - !!perl/regexp ^sep0.*$

=back

To simply match all nodes, use "C<any>" or IP Prefix "C<0.0.0.0/0>". All
regular expressions are anchored (that is, they must match the whole string).
To match no nodes we recommend an entry of "C<localhost>" in the setting.

=cut

sub check_node_only {
  my ($ip, $setting_name) = @_;

  my $config = setting($setting_name) || [];
  return 1 if not scalar @$config;

  return check_acl($ip, $config);
}

=head2 is_nbtstatable( $ip )

Given an IP address, returns C<true> if Netdisco on this host is permitted by
the local configuration to nbtstat the node.

The configuration items C<nbtstat_no> and C<nbtstat_only> are checked
against the given IP.

Returns false if the host is not permitted to nbtstat the target node.

=cut

sub is_nbtstatable {
  my $ip = shift;

  return _bail_msg("is_nbtstatable: node matched nbtstat_no")
    if check_node_no($ip, 'nbtstat_no');

  return _bail_msg("is_nbtstatable: node failed to match nbtstat_only")
    unless check_node_only($ip, 'nbtstat_only');

  return 1;
}

1;
