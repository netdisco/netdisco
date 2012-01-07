package Netdisco::DB::ResultSet::Device;
use base 'DBIx::Class::ResultSet';

sub carrying_vlan {
    my ($set, $vlan) = @_;
    return $set unless $vlan and $vlan =~ m/^\d+$/;

    return $set->search(
      {
        'vlans.vlan' => $vlan,
        'port_vlans.vlan' => $vlan,
      },
      {
        join => [qw/ port_vlans vlans /],
        prefetch => 'vlans',
        order_by => [qw/ me.dns me.ip /],
        columns => [qw/ me.ip me.dns me.model me.os me.vendor /],
      },
    );
}


1;
