package App::Netdisco::Util::Permission;

use strict;
use warnings;
use Dancer qw/:syntax :script/;

use Scalar::Util 'blessed';
use NetAddr::IP::Lite ':lower';
use App::Netdisco::Util::DNS 'hostname_from_ip';
use feature qw(state);
use Memoize;
use Class::Method::Modifiers 'fresh';
use Digest::MD5 qw(md5_base64);

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
setting C<$setting_name> matches, else returns false. If the setting is
undefined or empty, then C<check_acl_no> also returns false.

If C<$setting_name> is a valid setting, then it will be resolved to the access
control list, else we assume you passed an ACL entry or ACL.

See L<App::Netdisco::Manual::Configuration> for details of what C<$acl> may
contain.

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
setting C<$setting_name> matches, else returns false. If the setting is
undefined or empty, then C<check_acl_only> also returns true.

If C<$setting_name> is a valid setting, then it will be resolved to the access
control list, else we assume you passed an ACL entry or ACL.

See L<App::Netdisco::Manual::Configuration> for details of what C<$acl> may
contain.

=cut


sub check_acl_only {
  my ($thing, $setting_name) = @_;
  return 0 unless $thing and $setting_name;
  # logic to make an empty config be equivalent to 'any' (i.e. a match)
  my $config = (exists config->{"$setting_name"} ? setting($setting_name)
                                                 : $setting_name);
  return 1 if not $config # undef or empty string
              or ((ref [] eq ref $config) and not scalar @$config);
  return check_acl($thing, $config);
}

sub _construct_netaddr {

  my ($ctrarg) = @_;

  return NetAddr::IP::Lite->new($ctrarg) unless setting('memoize_acl'); 

  state $cache = {};
  my $hit = 1;
  if (!$cache->{$ctrarg}){
    $cache->{$ctrarg} = NetAddr::IP::Lite->new($ctrarg);
    $hit = 0;
  }

  my $entries = scalar keys %{$cache}; 
  #warning sprintf '_construct_netaddr %s hit: %s total entries: %s', 
  #  $ctrarg, $hit, scalar keys %{$cache} if ($entries % 500 == 0);
  return $cache->{$ctrarg}; 

}

=head2 check_acl( $ip | $instance, $acl_entry | \@acl )

Given an IP address or object instance, compares it to the items in C<< \@acl
>> then returns true or false. You can control whether any item must match or
all must match, and items can be negated to invert the match logic.

Accepts instances of classes representing Netdisco Devices, Netdisco Device
IPs, and L<NetAddr::IP> family objects.

There are several options for what C<< \@acl >> may contain. See
L<App::Netdisco::Manual::Configuration> for the details.

=cut

sub _real_ip {
  my ($thing) = @_;

  my $real_ip = $thing;
  if (blessed $thing) {
    $real_ip = ($thing->can('alias') ? $thing->alias : (
      $thing->can('ip') ? $thing->ip : (
        $thing->can('addr') ? $thing->addr : $thing )));
  }

  if (blessed $real_ip){
    return 0;
  }else{
    return $real_ip; 
  }

}

our $check_acl_subref  = sub { 
  my ($thing, $config) = @_;
  return 0 unless defined $thing and defined $config;

  my $real_ip = _real_ip($thing);
  return 0 if $real_ip eq 0; # class we do not understand

  $config  = [$config] if ref [] ne ref $config;
  my $addr = _construct_netaddr($real_ip) or return 0;
  my $all  = (scalar grep {m/^op:and$/} @$config);
  my $name = undef; # only look up once, and only if qr// is used
  my $ropt = { retry => 1, retrans => 1, udp_timeout => 1, tcp_timeout => 2 };

  INLIST: foreach (@$config) {
      my $item = $_; # must copy so that we can modify safely
      next INLIST if $item eq 'op:and';

      if (ref qr// eq ref $item) {
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
                  my $ip = _construct_netaddr($header . sprintf('%x',$part) . '/128')
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
                  my $ip = _construct_netaddr($header . $part . '/32')
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

      my $ip = _construct_netaddr($item)
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
};

if (setting('memoize_acl')){

  fresh 'check_acl' => memoize( $check_acl_subref,  
    NORMALIZER => sub { 
       my $stringinput = $_[0] . " " . $_[1]; 
       my $norminput = _real_ip($_[0]) . " " . md5_base64(join(" ", @{$_[1]})); 
       #warning $stringinput . " ::::-> ". $norminput; 
       #return $stringinput;
       return $norminput;
    }
  );

} else {

  fresh 'check_acl' => $check_acl_subref; 

}

1;
