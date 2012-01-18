package Netdisco::DB::ResultSet::Device;
use base 'DBIx::Class::ResultSet';

use strict;
use warnings FATAL => 'all';
use NetAddr::IP::Lite ':lower';

# override the built-in so we can munge some columns
sub find {
  my ($set, $ip, $attr) = @_;
  $attr ||= {};

  return $set->SUPER::find($ip,
    {
      %$attr,
      '+select' => [
        \"replace(age(timestamp 'epoch' + uptime / 100 * interval '1 second', timestamp '1970-01-01 00:00:00-00')::text, 'mon', 'month')",
        \"to_char(last_discover, 'YYYY-MM-DD HH24:MI')",
        \"to_char(last_macsuck,  'YYYY-MM-DD HH24:MI')",
        \"to_char(last_arpnip,   'YYYY-MM-DD HH24:MI')",
      ],
      '+as' => [qw/ uptime last_discover last_macsuck last_arpnip /],
    }
  );
}

# finds distinct values of a col for use in form selections
sub get_distinct {
  my ($set, $col) = @_;
  return $set unless $col;

  return $set->search({},
    {
      columns => [$col],
      order_by => $col,
      distinct => 1
    }
  )->get_column($col)->all;
}

sub by_field {
    my ($set, $p) = @_;
    return $set unless ref {} eq ref $p;
    my $op = $p->{matchall} ? '-and' : '-or';

    # this is a bit of a dreadful hack to catch junk entry
    # whilst avoiding returning all devices in the DB
    my $ip = ($p->{ip} ?
      (NetAddr::IP::Lite->new($p->{ip}) || NetAddr::IP::Lite->new('255.255.255.255'))
      : undef);

    return $set->search(
      {
        $op => [
          ($p->{name} ? ('me.name' =>
            { '-ilike' => "\%$p->{name}\%" }) : ()),
          ($p->{location} ? ('me.location' =>
            { '-ilike' => "\%$p->{location}\%" }) : ()),
          ($p->{description} ? ('me.description' =>
            { '-ilike' => "\%$p->{description}\%" }) : ()),
          ($p->{model} ? ('me.model' =>
            { '-in' => $p->{model} }) : ()),
          ($p->{os_ver} ? ('me.os_ver' =>
            { '-in' => $p->{os_ver} }) : ()),
          ($p->{vendor} ? ('me.vendor' =>
            { '-in' => $p->{vendor} }) : ()),
          ($p->{dns} ? (
          -or => [
            'me.dns'      => { '-ilike' => "\%$p->{dns}\%" },
            'device_ips.dns' => { '-ilike' => "\%$p->{dns}\%" },
          ]) : ()),
          ($ip ? (
          -or => [
            'me.ip'  => { '<<=' => $ip->cidr },
            'device_ips.alias' => { '<<=' => $ip->cidr },
          ]) : ()),
        ],
      },
      {
        order_by => [qw/ me.dns me.ip /],
        join => 'device_ips',
        distinct => 1,
      }
    );
}

sub by_any {
    my ($set, $q) = @_;
    return $set unless $q;
    $q = "\%$q\%" if $q !~ m/\%/;

    return $set->search(
      {
        -or => [
          'me.contact'  => { '-ilike' => $q },
          'me.serial'   => { '-ilike' => $q },
          'me.location' => { '-ilike' => $q },
          'me.name'     => { '-ilike' => $q },
          'me.description' => { '-ilike' => $q },
          -or => [
            'me.dns'      => { '-ilike' => $q },
            'device_ips.dns' => { '-ilike' => $q },
          ],
          -or => [
            'me.ip::text'  => { '-ilike' => $q },
            'device_ips.alias::text' => { '-ilike' => $q },
          ],
        ],
      },
      {
        order_by => [qw/ me.dns me.ip /],
        join => 'device_ips',
        distinct => 1,
      }
    );
}

sub carrying_vlan {
    my ($set, $vlan) = @_;
    return $set unless $vlan and $vlan =~ m/^\d+$/;

    return $set->search(
      {
        'vlans.vlan' => $vlan,
        'port_vlans.vlan' => $vlan,
      },
      {
        order_by => [qw/ me.dns me.ip /],
        columns => [qw/ me.ip me.dns me.model me.os me.vendor /],
        join => 'port_vlans',
        prefetch => 'vlans',
      },
    );
}

sub carrying_vlan_name {
    my ($set, $name) = @_;
    return $set unless $name;
    $name = "\%$name\%" if $name !~ m/\%/;

    return $set->search(
      {
        'vlans.description' => { '-ilike' => $name },
      },
      {
        order_by => [qw/ me.dns me.ip /],
        columns => [qw/ me.ip me.dns me.model me.os me.vendor /],
        prefetch => 'vlans',
      },
    );
}

1;
