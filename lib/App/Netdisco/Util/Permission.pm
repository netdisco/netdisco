package App::Netdisco::Util::Permission;

use strict;
use warnings;
use Dancer qw/:syntax :script/;

use Scalar::Util qw/blessed reftype/;
use NetAddr::IP::Lite ':lower';
use App::Netdisco::Util::DNS 'hostname_from_ip';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/check_acl check_acl_no check_acl_only/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Permission

=head1 DESCRIPTION

Helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 check_acl_no( $ip | $instance, $setting_name | $acl_entry | \@acl )

Given an IP address or object instance, returns true if the configuration
setting C<$setting_name> matches, else returns false. If the content of the
setting is undefined or empty, then C<check_acl_no> also returns false.

If C<$setting_name> is a valid setting, then it will be resolved to the access
control list, else we assume you passed an ACL entry or ACL.

See L<the Netdisco wiki|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
for details of what C<$acl> may contain.

=cut

sub check_acl_no {
  my ($thing, $setting_name) = @_;
  return 1 unless $thing and $setting_name;
  my $config = (exists config->{"$setting_name"} ? setting($setting_name)
                                                 : $setting_name);
  return check_acl($thing, $config);
}

=head2 check_acl_only( $ip | $instance, $setting_name | $acl_entry | \@acl )

Given an IP address or object instance, returns true if the configuration
setting C<$setting_name> matches, else returns false. If the content of the
setting is undefined or empty, then C<check_acl_only> also returns true.

If C<$setting_name> is a valid setting, then it will be resolved to the access
control list, else we assume you passed an ACL entry or ACL.

See L<the Netdisco wiki|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
for details of what C<$acl> may contain.

=cut

sub check_acl_only {
  my ($thing, $setting_name) = @_;
  return 0 unless $thing and $setting_name;
  # logic to make an empty config be equivalent to 'any' (i.e. a match)
  my $config = (exists config->{"$setting_name"} ? setting($setting_name)
                                                 : $setting_name);
  return 1 if not $config # undef or empty string
              or ((ref [] eq ref $config) and not scalar @$config);
  return check_acl($thing, $config);
}

=head2 check_acl( $ip | $instance, $acl_entry | \@acl )

Given an IP address or object instance, compares it to the items in C<< \@acl
>> then returns true or false. You can control whether any item must match or
all must match, and items can be negated to invert the match logic.

Accepts instances of classes representing Netdisco Devices, Netdisco Device
IPs, and L<NetAddr::IP> family objects.

There are several options for what C<< \@acl >> may contain. See
L<the Netdisco wiki|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
for the details.

=cut

sub check_acl {
  my ($thing, $config) = @_;
  return 0 unless defined $thing and defined $config;

  my $real_ip = $thing;
  if (blessed $thing) {
    $real_ip = ($thing->can('alias') ? $thing->alias : (
      $thing->can('ip') ? $thing->ip : (
        $thing->can('addr') ? $thing->addr : $thing )));
  }
  return 0 if !defined $real_ip
    or blessed $real_ip; # class we do not understand

  $config  = [$config] if ref '' eq ref $config;
  if (ref [] ne ref $config) {
    error "error: acl is not a single item or list (cannot compare to $real_ip)";
    return 0;
  }
  my $all  = (scalar grep {$_ eq 'op:and'} @$config);

  # common case of using plain IP in ACL, so string compare for speed
  my $find = (scalar grep {not reftype $_ and $_ eq $real_ip} @$config);
  return 1 if $find and not $all;

  my $addr = NetAddr::IP::Lite->new($real_ip) or return 0;
  my $name = undef; # only look up once, and only if qr// is used
  my $ropt = { retry => 1, retrans => 1, udp_timeout => 1, tcp_timeout => 2 };
  my $qref = ref qr//;

  INLIST: foreach (@$config) {
      my $item = $_; # must copy so that we can modify safely
      next INLIST if !defined $item or $item eq 'op:and';

      if ($qref eq ref $item) {
          $name = ($name || hostname_from_ip($addr->addr, $ropt) || '!!none!!');
          if ($name =~ $item) {
            return 1 if not $all;
          }
          else {
            return 0 if $all;
          }
          next INLIST;
      }

      my $neg = ($item =~ s/^!//);

      if ($item =~ m/^group:(.+)$/) {
          my $group = $1;
          setting('host_groups')->{$group} ||= [];

          if ($neg xor check_acl($thing, setting('host_groups')->{$group})) {
            return 1 if not $all;
          }
          else {
            return 0 if $all;
          }
          next INLIST;
      }

      if ($item =~ m/^([^:]+):([^:]+)$/) {
          my $prop  = $1;
          my $match = $2;

          # if not an object, we can't do much with properties
          next INLIST unless blessed $thing;

          # lazy version of vendor: and model:
          if ($neg xor ($thing->can($prop) and defined eval { $thing->$prop }
              and $thing->$prop =~ m/^$match$/)) {
            return 1 if not $all;
          }
          else {
            return 0 if $all;
          }
          next INLIST;
      }

      if ($item =~ m/[:.]([a-f0-9]+)-([a-f0-9]+)$/i) {
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

      # could be something in error, and IP/host is only option left
      next INLIST if ref $item;

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
