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
        order_by => [qw/ me.dns me.ip /],
        columns => [qw/ me.ip me.dns me.model me.os me.vendor /],
        join => 'port_vlans',
        prefetch => 'vlans',
      },
    );
}


1;
