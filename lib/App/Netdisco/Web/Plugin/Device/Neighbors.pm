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

ajax '/ajax/data/device/alldevicelinks' => require_login sub {
    my $q = param('q');
    my %data = ( nodes => [], links => [] );

    my $vlan = param('vlan');
    undef $vlan if (defined $vlan and $vlan !~ m/^\d+$/);

    my @devices = schema('netdisco')->resultset('Device')->search({}, {
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
      columns => ['ip', 'dns', 'name'],
      '+select' => [\'row_number() over()'], '+as' => ['row_number'],
    })->all;

    my %id_for = ();
    my $domain = quotemeta( setting('domain_suffix') || '' );
    foreach my $device (@devices) {
      $id_for{$device->{ip}} = $device->{'row_number'};
      (my $name = ($device->{dns} || lc($device->{name}) || $device->{ip})) =~ s/$domain$//;

      push @{$data{'nodes'}}, {
        ID => $device->{row_number},
        SIZEVALUE => 3000,
        COLORVALUE => 10,
        LABEL => $name,
      };
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
      push @{$data{'links'}}, {
        FROMID => $id_for{$l->{left_ip}},
        TOID   => $id_for{$l->{right_ip}},
      };
    }

    content_type('application/json');
    to_json({data => \%data});
};

true;
