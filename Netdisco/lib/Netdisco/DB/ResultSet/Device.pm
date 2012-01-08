package Netdisco::DB::ResultSet::Device;
use base 'DBIx::Class::ResultSet';

use NetAddr::IP::Lite ':lower';

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
        join => 'device_ips',
        group_by => 'me.ip',
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
        join => 'device_ips',
        group_by => 'me.ip',
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

1;
