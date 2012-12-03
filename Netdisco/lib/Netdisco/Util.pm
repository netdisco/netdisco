package Netdisco::Util;

use strict;
use warnings FATAL => 'all';

use SNMP::Info;
use Config::Tiny;
use File::Slurp;
use Try::Tiny;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/load_nd_config get_device snmp_connect sort_port/;
our %EXPORT_TAGS = (port_control => [qw/get_device snmp_connect/]);

sub load_nd_config {
  my $file = shift or die "missing netdisco config file name.\n";
  my $config = {};

  if (-e $file) {
      # read file and alter line continuations to be single lines
      my $config_content = read_file($file);
      $config_content =~ s/\\\n//sg;

      # parse config naively as .ini
      $config = Config::Tiny->new()->read_string($config_content);
      die (Config::Tiny->errstr ."\n") if !defined $config;
  }

  return $config;
}

sub get_device {
  my $ip = shift;

  my $alias = schema('netdisco')->resultset('DeviceIp')
    ->search({alias => $ip})->first;
  return if not eval { $alias->ip };

  return schema('netdisco')->resultset('Device')
    ->find({ip => $alias->ip});
}

sub build_mibdirs {
  my $nd_config = var('nd_config')
    or die "Cannot call build_mibdirs without Dancer and nd_config.\n";

  my $mibhome  = $nd_config->{_}->{mibhome};
  (my $mibdirs = $nd_config->{_}->{mibdirs}) =~ s/\s+//g;

  $mibdirs =~ s/\$mibhome/$mibhome/g;
  return [ split /,/, $mibdirs ];
}

sub snmp_connect {
  my $ip = shift;
  my $nd_config = var('nd_config')
    or die "Cannot call snmp_connect without Dancer and nd_config.\n";

  # get device details from db
  my $device = get_device($ip)
    or return ();

  # TODO: really only supporing v2c at the moment
  my %snmp_args = (
    DestHost => $device->ip,
    Version => ($device->snmp_ver || $nd_config->{_}->{snmpver} || 2),
    Retries => ($nd_config->{_}->{snmpretries} || 2),
    Timeout => ($nd_config->{_}->{snmptimeout} || 1000000),
    MibDirs => build_mibdirs(),
    AutoSpecify => 1,
    Debug => ($ENV{INFO_TRACE} || 0),
  );

  (my $comm = $nd_config->{_}->{community_rw}) =~ s/\s+//g;
  my @communities = split /,/, $comm;

  my $info = undef;
  COMMUNITY: foreach my $c (@communities) {
      try {
          $info = SNMP::Info->new(%snmp_args, Community => $c);
          last COMMUNITY if (
            $info
            and (not defined $info->error)
            and length $info->uptime
          );
      };
  }

  return $info;
}

=head2 sort_port( $a, $b )

Sort port names of various types used by device vendors. Interface is as
Perl's own C<sort> - two input args and an integer return value.

=cut

sub sort_port {
    my ($aval, $bval) = @_;

    # hack for foundry "10GigabitEthernet" -> cisco-like "TenGigabitEthernet"
    $aval = "Ten$1" if $aval =~ qr/^10(GigabitEthernet.+)$/;
    $bval = "Ten$1" if $bval =~ qr/^10(GigabitEthernet.+)$/;

    my $numbers        = qr{^(\d+)$};
    my $numeric        = qr{^([\d\.]+)$};
    my $dotted_numeric = qr{^(\d+)\.(\d+)$};
    my $letter_number  = qr{^([a-zA-Z]+)(\d+)$};
    my $wordcharword   = qr{^([^:\/.]+)[\ :\/\.]+([^:\/.]+)(\d+)?$}; #port-channel45
    my $netgear        = qr{^Slot: (\d+) Port: (\d+) }; # "Slot: 0 Port: 15 Gigabit - Level"
    my $ciscofast      = qr{^
                            # Word Number slash (Gigabit0/)
                            (\D+)(\d+)[\/:]
                            # Groups of symbol float (/5.5/5.5/5.5), separated by slash or colon
                            ([\/:\.\d]+)
                            # Optional dash (-Bearer Channel)
                            (-.*)?
                            $}x;

    my @a = (); my @b = ();

    if ($aval =~ $dotted_numeric) {
        @a = ($1,$2);
    } elsif ($aval =~ $letter_number) {
        @a = ($1,$2);
    } elsif ($aval =~ $netgear) {
        @a = ($1,$2);
    } elsif ($aval =~ $numbers) {
        @a = ($1);
    } elsif ($aval =~ $ciscofast) {
        @a = ($2,$1);
        push @a, split(/[:\/]/,$3), $4;
    } elsif ($aval =~ $wordcharword) {
        @a = ($1,$2,$3);
    } else {
        @a = ($aval);
    }

    if ($bval =~ $dotted_numeric) {
        @b = ($1,$2);
    } elsif ($bval =~ $letter_number) {
        @b = ($1,$2);
    } elsif ($bval =~ $netgear) {
        @b = ($1,$2);
    } elsif ($bval =~ $numbers) {
        @b = ($1);
    } elsif ($bval =~ $ciscofast) {
        @b = ($2,$1);
        push @b, split(/[:\/]/,$3),$4;
    } elsif ($bval =~ $wordcharword) {
        @b = ($1,$2,$3);
    } else {
        @b = ($bval);
    }

    # Equal until proven otherwise
    my $val = 0;
    while (scalar(@a) or scalar(@b)){
        # carried around from the last find.
        last if $val != 0;

        my $a1 = shift @a;
        my $b1 = shift @b;

        # A has more components - loses
        unless (defined $b1){
            $val = 1;
            last;
        }

        # A has less components - wins
        unless (defined $a1) {
            $val = -1;
            last;
        }

        if ($a1 =~ $numeric and $b1 =~ $numeric){
            $val = $a1 <=> $b1;
        } elsif ($a1 ne $b1) {
            $val = $a1 cmp $b1;
        }
    }

    return $val;
}

1;
