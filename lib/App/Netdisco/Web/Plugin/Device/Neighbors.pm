package App::Netdisco::Web::Plugin::Device::Neighbors;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_device_tab({ tag => 'netmap', label => 'Neighbors' });

ajax '/ajax/content/device/netmap' => require_login sub {
    content_type('text/html');
    template 'ajax/device/netmap.tt', {}, { layout => undef };
};

ajax '/ajax/data/device/netmap' => require_login sub {
    my $q = param('q');
    my $qdev = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    my $vlan = param('vlan');
    undef $vlan if (defined $vlan and $vlan !~ m/^\d+$/);

    my @devices = schema('netdisco')->resultset('Device')->search({}, {
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
      columns => ['ip', 'dns', 'name'],
      '+select' => [\'row_number() over()'], '+as' => ['row_number'],
    })->all;

    my %id_for = ();
    my %v3data = ( nodes => {}, links => [] );
    my %v4data = ( nodes => [], links => [] );
    my $domain = quotemeta( setting('domain_suffix') || '' );

    foreach my $device (@devices) {
      $id_for{$device->{ip}} = $device->{'row_number'};
      (my $name = ($device->{dns} || lc($device->{name}) || $device->{ip})) =~ s/$domain$//;

      $v3data{nodes}->{ ($device->{row_number} - 1) } = {
        ID => $device->{row_number},
        SIZEVALUE => 3000,
        COLORVALUE => 10,
        LABEL => $name,
      };
      push @{$v4data{'nodes'}}, { index => ($device->{row_number} - 1) };

      $v3data{'centernode'} = $device->{row_number}
        if $qdev and $qdev->in_storage and $device->{ip} eq $qdev->ip;
    }

    my $rs = schema('netdisco')->resultset('Virtual::DeviceLinks')->search({}, {
      columns => [qw/left_ip right_ip/],
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    });

    if ($vlan) {
        $rs = $rs->search({
          'left_vlans.vlan' => $vlan,
          'right_vlans.vlan' => $vlan,
        }, {
          join => [qw/left_vlans right_vlans/],
        });
    }

    while (my $l = $rs->next) {
      push @{$v3data{'links'}}, {
        FROMID => $id_for{$l->{left_ip}},
        TOID   => $id_for{$l->{right_ip}},
      };
      push @{$v4data{'links'}}, {
        source => ($id_for{$l->{left_ip}} - 1),
        target => ($id_for{$l->{right_ip}} - 1),
      };
    }

    content_type('application/json');
    to_json({ v3 => \%v3data, v4 => \%v4data});
};

true;
