package App::Netdisco::Util::Permission;

use strict;
use warnings;
use Dancer qw/:syntax :script/;

use Scalar::Util qw/blessed reftype/;
use NetAddr::IP::Lite ':lower';
use Algorithm::Cron;

use App::Netdisco::Util::DNS 'hostname_from_ip';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/check_acl check_acl_no check_acl_only acl_matches acl_matches_only/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Permission

=head1 DESCRIPTION

Helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 acl_matches( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

Given an IP address, object instance, or hash, returns true if the
configuration setting C<$setting_name> matches, else returns false.

Usage of this function is strongly advised to be of the form:

 QUIT/SKIP IF acl_matches

The function fails safe, so if the content of the setting or ACL is undefined
or an empty string, then C<acl_matches> also returns true.

If C<$setting_name> is a valid setting, then it will be resolved to the access
control list, else we assume you passed an ACL entry or ACL.

See L<the Netdisco wiki|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
for details of what C<$acl> may contain.

=cut

sub acl_matches {
  my ($thing, $setting_name) = @_;
  # fail-safe so undef config should return true
  return true unless $thing and $setting_name;
  my $config = (exists config->{"$setting_name"} ? setting($setting_name)
                                                 : $setting_name);
  return check_acl($thing, $config);
}

=head2 check_acl_no( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

This is an alias for L<acl_matches>.

=cut

sub check_acl_no { goto &acl_matches }

=head2 acl_matches_only( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

Given an IP address, object instance, or hash, returns true if the
configuration setting C<$setting_name> matches, else returns false.

Usage of this function is strongly advised to be of the form:

 QUIT/SKIP UNLESS acl_matches_only

The function fails safe, so if the content of the setting or ACL is undefined
or an empty string, then C<acl_matches_only> also returns false.

Further, if the setting or ACL resolves to a list but the list has no items,
then C<acl_matches_only> returns true (as if there is a successful match).

If C<$setting_name> is a valid setting, then it will be resolved to the access
control list, else we assume you passed an ACL entry or ACL.

See L<the Netdisco wiki|https://github.com/netdisco/netdisco/wiki/Configuration#access-control-lists>
for details of what C<$acl> may contain.

=cut

sub acl_matches_only {
  my ($thing, $setting_name) = @_;
  # fail-safe so undef config should return false
  return false unless $thing and $setting_name;
  my $config = (exists config->{"$setting_name"} ? setting($setting_name)
                                                 : $setting_name);
  # logic to make an empty config be equivalent to 'any' (i.e. a match)
  # empty list check means truth check passes for match or empty list
  return true if not $config # undef or empty string
              or ((ref [] eq ref $config) and not scalar @$config);
  return check_acl($thing, $config);
}

=head2 check_acl_only( $ip | $object | \%hash | \@item_list, $setting_name | $acl_entry | \@acl )

This is an alias for L<acl_matches_only>.

=cut

sub check_acl_only { goto &acl_matches_only }

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
  return false unless defined $things and defined $config;
  return false if ref [] eq ref $things and not scalar @$things;
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
    return false;
  }
  my $all  = (scalar grep {$_ eq 'op:and'} @$config);

  # common case of using plain IP in ACL, so string compare for speed
  my $find = (scalar grep {not reftype $_ and $_ eq $real_ip} @$config);
  return true if $real_ip and $find and not $all;

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
            return true if not $all;
          }
          else {
            return false if $all;
          }
          next RULE;
      }

      my $neg = ($rule =~ s/^!//);

      if ($rule =~ m/^group:(.+)$/) {
          my $group = $1;
          setting('host_groups')->{$group} ||= [];

          if ($neg xor check_acl($things, setting('host_groups')->{$group})) {
            return true if not $all;
          }
          else {
            return false if $all;
          }
          next RULE;
      }

      if ($rule =~ m/^tag:(.+)$/) {
          my $tag = $1;
          my $found = false;

          ITEM: foreach my $item (@$things) {
              if (blessed $item and $item->can('tags')) {
                  if ($neg xor scalar grep {$_ eq $tag} @{ $item->tags || [] }) {
                    return true if not $all;
                    $found = true;
                    last ITEM;
                  }
              }
              elsif (ref {} eq ref $item and exists $item->{'tags'}) {
                  if ($neg xor scalar grep {$_ eq $tag} @{ $item->{'tags'} || [] }) {
                    return true if not $all;
                    $found = true;
                    last ITEM;
                  }
              }
          }

          return false if $all and not $found;
          next RULE;
      }

      # cf:customfield:val
      if ($rule =~ m/^cf:([^:]+):(.*)$/) {
          my $prop  = $1;
          my $match = $2 || '';
          my $found = false;

          # custom field exists, undef is allowed to match empty string
          ITEM: foreach my $item (@$things) {
              my $cf = {};
              if (blessed $item and $item->can('custom_fields')) {
                  $cf = from_json ($item->custom_fields || '{}');
              }
              elsif (ref {} eq ref $item and exists $item->{'custom_fields'}) {
                  $cf = from_json ($item->{'custom_fields'} || '{}');
              }

              if (ref {} eq ref $cf and exists $cf->{$prop}) {
                  if ($neg xor
                          ((!defined $cf->{$prop} and $match eq q{})
                          or
                          (defined $cf->{$prop} and ref $cf->{$prop} eq q{} and $cf->{$prop} =~ m/^$match$/)) ) {
                    return true if not $all;
                    $found = true;
                    last ITEM;
                  }
              }
          }

          # missing custom field matches empty string
          # #1348 or matches string if $neg is set
          # (which is done in a second pass to allow all @$things to be
          # inspected for existing custom fields)
          if (! $found and ($match eq q{} and not $neg) or (length $match and $neg)) {

              ITEM: foreach my $item (@$things) {
                  my $cf = {};
                  if (blessed $item and $item->can('custom_fields')) {
                      $cf = from_json ($item->custom_fields || '{}');
                  }
                  elsif (ref {} eq ref $item and exists $item->{'custom_fields'}) {
                      $cf = from_json ($item->{'custom_fields'} || '{}');
                  }

                  # empty or missing property
                  if (ref {} eq ref $cf and ! exists $cf->{$prop}) {
                      return true if not $all;
                      $found = true;
                      last ITEM;
                  }
              }
          }

          return false if $all and not $found;
          next RULE;
      }

      # prop:val
      # with a check that prop isn't just the first part of a v6 addr
      if ($rule =~ m/^([^:]+):(.*)$/ and $1 !~ m/^[a-f0-9]+$/i) {
          my $prop  = $1;
          my $match = $2 || '';
          my $found = false;

          # property exists, undef is allowed to match empty string
          ITEM: foreach my $item (@$things) {
              if (blessed $item and $item->can($prop)) {
                  if ($neg xor
                          ((!defined eval { $item->$prop } and $match eq q{})
                           or
                           (defined eval { $item->$prop } and ref $item->$prop eq q{} and $item->$prop =~ m/^$match$/)) ) {
                    return true if not $all;
                    $found = true;
                    last ITEM;
                  }
              }
              elsif (ref {} eq ref $item and exists $item->{$prop}) {
                  if ($neg xor
                          ((!defined $item->{$prop} and $match eq q{})
                           or
                           (defined $item->{$prop} and ref $item->{$prop} eq q{} and $item->{$prop} =~ m/^$match$/)) ) {
                    return true if not $all;
                    $found = true;
                    last ITEM;
                  }
              }
          }

          # missing property matches empty string
          # #1348 or matches string if $neg is set
          # (which is done in a second pass to allow all @$things to be
          # inspected for existing properties)
          if (! $found and ($match eq q{} and not $neg) or (length $match and $neg)) {

              ITEM: foreach my $item (@$things) {
                  if (blessed $item and ! $item->can($prop)) {
                      return true if not $all;
                      $found = true;
                      last ITEM;
                  }
                  elsif (ref {} eq ref $item and ! exists $item->{$prop}) {
                      return true if not $all;
                      $found = true;
                      last ITEM;
                  }
              }
          }

          return false if $all and not $found;
          next RULE;
      }

      if ($rule =~ m/^\S+\s+\S+\s+\S+\s+\S+\s+\S+/i) {
          my $win_start = time - (time % 60) - 1;
          my $win_end   = $win_start + 60;
          my $cron = Algorithm::Cron->new(
            base => 'local',
            crontab => $rule,
          ) or next RULE;

          if ($neg xor ($cron->next_time($win_start) <= $win_end)) {
              return true if not $all;
          }
          else {
              return false if $all;
          }
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
                    return true if not $all;
                    next RULE;
                  }
              }
              return false if (not $neg and $all);
              return true if ($neg and not $all);
          }
          else {
              next RULE if $addr->bits != 32 and not $all;

              (my $header = $rule) =~ s/\.[^.]+$/./;
              foreach my $part ($first .. $last) {
                  my $ip = NetAddr::IP::Lite->new($header . $part . '/32')
                    or next;
                  if ($neg xor ($ip == $addr)) {
                    return true if not $all;
                    next RULE;
                  }
              }
              return false if (not $neg and $all);
              return true if ($neg and not $all);
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
        return true if not $all;
      }
      else {
        return false if $all;
      }

      next RULE;
  }

  return ($all ? true : false);
}

true;
