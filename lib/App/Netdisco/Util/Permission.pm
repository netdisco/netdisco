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

=head2 check_acl_no( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

Given an IP address, object instance, or hash, returns true if the
configuration setting C<$setting_name> matches, else returns false. If the
content of the setting is undefined or empty, then C<check_acl_no> also
returns false.

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

=head2 acl_matches( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

This is an alias for L<check_acl_no>.

=cut

sub acl_matches { goto &check_acl_no }

=head2 check_acl_only( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

Given an IP address, object instance, or hash, returns true if the
configuration setting C<$setting_name> matches, else returns false. If the
content of the setting is undefined or empty, then C<check_acl_only> also
returns true.

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

=head2 check_acl( $ip | $object | \%hash | \@item_list, $acl_entry | \@acl )

Given an IP address, object instance, or hash, compares it to the items in
C<< \@acl >> then returns true or false. You can control whether any item must
match or all must match, and items can be negated to invert the match logic.

Also accepts an array reference of multiple IP addresses, object instances,
and hashes, and will test against each in turn, for each ACL rule.

The slots C<alias>, C<ip>, C<switch>, and C<addr> are looked for in the
instance or hash and used to compare a bare IP address (so it works with most
Netdisco database classes, and the L<NetAddr::IP> class). Any instance or hash
slot can be used as an ACL named property.

There are several options for what C<< \@acl >> may contain. See
L<the Netdisco wiki|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
for the details.

=cut

sub check_acl {
  my ($things, $config) = @_;
  return 0 unless defined $things and defined $config;
  return 0 if ref [] eq ref $things and not scalar @$things;
  $things = [$things] if ref [] ne ref $things;

  my $real_ip = ''; # valid to be empty
  ITEM: foreach my $item (@$things) {
      foreach my $slot (qw/alias ip switch addr/) {
          if (blessed $item) {
              $real_ip = $item->$slot if $item->can($slot)
                                         and eval { $item->$slot };
          }
          elsif (ref {} eq ref $item) {
              $real_ip = $item->{$slot} if exists $item->{$slot}
                                           and $item->{$slot};
          }
          last ITEM if $real_ip;
      }
  }
  ITEM: foreach my $item (@$things) {
      last ITEM if $real_ip;
      $real_ip = $item if (ref $item eq q{}) and $item;
  }

  $config  = [$config] if ref $config eq q{};
  if (ref [] ne ref $config) {
    error "error: acl is not a single item or list (cannot compare to '$real_ip')";
    return 0;
  }
  my $all  = (scalar grep {$_ eq 'op:and'} @$config);

  # common case of using plain IP in ACL, so string compare for speed
  my $find = (scalar grep {not reftype $_ and $_ eq $real_ip} @$config);
  return 1 if $real_ip and $find and not $all;

  my $addr = NetAddr::IP::Lite->new($real_ip);
  my $name = undef; # only look up once, and only if qr// is used
  my $ropt = { retry => 1, retrans => 1, udp_timeout => 1, tcp_timeout => 2 };
  my $qref = ref qr//;

  RULE: foreach (@$config) {
      my $rule = $_; # must copy so that we can modify safely
      next RULE if !defined $rule or $rule eq 'op:and';

      if ($qref eq ref $rule) {
          # if no IP addr, cannot match its dns
          next RULE unless $addr;

          $name = ($name || hostname_from_ip($addr->addr, $ropt) || '!!none!!');
          if ($name =~ $rule) {
            return 1 if not $all;
          }
          else {
            return 0 if $all;
          }
          next RULE;
      }

      my $neg = ($rule =~ s/^!//);

      if ($rule =~ m/^group:(.+)$/) {
          my $group = $1;
          setting('host_groups')->{$group} ||= [];

          if ($neg xor check_acl($things, setting('host_groups')->{$group})) {
            return 1 if not $all;
          }
          else {
            return 0 if $all;
          }
          next RULE;
      }

      if ($rule =~ m/^([^:]+):([^:]*)$/) {
          my $prop  = $1;
          my $match = $2 || '';

          # prop:val
          ITEM: foreach my $item (@$things) {
              if (blessed $item) {
                  if ($neg xor ($item->can($prop) and
                                  defined eval { $item->$prop } and
                                  ref $item->$prop eq q{}
                                  and $item->$prop =~ m/^$match$/) ) {
                    return 1 if not $all;
                    last ITEM;
                  }
                  # empty or missing property
                  elsif ($neg xor ($match eq q{} and
                                     (!defined eval { $item->$prop } or $item->$prop eq q{})) ) {
                    return 1 if not $all;
                    last ITEM;
                  }
              }
              elsif (ref {} eq ref $item) {
                  if ($neg xor (exists $item->{$prop} and
                                  defined $item->{$prop} and
                                  ref $item->{$prop} eq q{}
                                  and $item->{$prop} =~ m/^$match$/) ) {
                    return 1 if not $all;
                    last ITEM;
                  }
                  # empty or missing property
                  elsif ($neg xor ($match eq q{} and
                                     (!defined $item->{$prop} or $item->{$prop} eq q{})) ) {
                    return 1 if not $all;
                    last ITEM;
                  }
              }
          }
          return 0 if $all;
          next RULE;
      }

      if ($rule =~ m/[:.]([a-f0-9]+)-([a-f0-9]+)$/i) {
          my $first = $1;
          my $last  = $2;

          # if no IP addr, cannot match IP range
          next RULE unless $addr;

          if ($rule =~ m/:/) {
              next RULE if $addr->bits != 128 and not $all;

              $first = hex $first;
              $last  = hex $last;

              (my $header = $rule) =~ s/:[^:]+$/:/;
              foreach my $part ($first .. $last) {
                  my $ip = NetAddr::IP::Lite->new($header . sprintf('%x',$part) . '/128')
                    or next;
                  if ($neg xor ($ip == $addr)) {
                    return 1 if not $all;
                    next RULE;
                  }
              }
              return 0 if (not $neg and $all);
              return 1 if ($neg and not $all);
          }
          else {
              next RULE if $addr->bits != 32 and not $all;

              (my $header = $rule) =~ s/\.[^.]+$/./;
              foreach my $part ($first .. $last) {
                  my $ip = NetAddr::IP::Lite->new($header . $part . '/32')
                    or next;
                  if ($neg xor ($ip == $addr)) {
                    return 1 if not $all;
                    next RULE;
                  }
              }
              return 0 if (not $neg and $all);
              return 1 if ($neg and not $all);
          }
          next RULE;
      }

      # could be something in error, and IP/host is only option left
      next RULE if ref $rule;

      # if no IP addr, cannot match IP prefix
      next RULE unless $addr;

      my $ip = NetAddr::IP::Lite->new($rule)
        or next RULE;
      next RULE if $ip->bits != $addr->bits and not $all;

      if ($neg xor ($ip->contains($addr))) {
        return 1 if not $all;
      }
      else {
        return 0 if $all;
      }
      next RULE;
  }

  return ($all ? 1 : 0);
}

1;
