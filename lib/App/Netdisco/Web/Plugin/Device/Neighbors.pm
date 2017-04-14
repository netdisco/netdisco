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

sub _get_name {
    my $ip = shift;
    my $domain = quotemeta( setting('domain_suffix') || '' );

    (my $dns = (var('devices')->{$ip} || '')) =~ s/$domain$//;
    return ($dns || $ip);
}

sub _add_children {
    my ($ptr, $childs, $step, $limit) = @_;

    return $step if $limit and $step > $limit;
    my @legit = ();
    my $max = $step;

    foreach my $c (@$childs) {
        next if exists var('seen')->{$c};
        var('seen')->{$c}++;
        push @legit, $c;
        push @{$ptr}, {
          name => _get_name($c),
          fullname => (var('devices')->{$c} || $c),
          ip => $c,
        };
    }

    for (my $i = 0; $i < @legit; $i++) {
        $ptr->[$i]->{children} = [];
        my $nm = _add_children($ptr->[$i]->{children}, var('links')->{$legit[$i]},
          ($step + 1), $limit);
        $max = $nm if $nm > $max;
    }

    return $max;
}

# d3 seems not to use proper ajax semantics, so get instead of ajax
get '/ajax/data/device/netmap' => require_login sub {
    my $q = param('q');

    my $vlan = param('vlan');
    undef $vlan if (defined $vlan and $vlan !~ m/^\d+$/);

    my $depth = (param('depth') || 8);
    undef $depth if (defined $depth and $depth !~ m/^\d+$/);

    my $device = schema('netdisco')->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);
    my $start = $device->ip;

    my @devices = schema('netdisco')->resultset('Device')->search({}, {
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
      columns => ['ip', 'dns'],
    })->all;
    var(devices => { map { $_->{ip} => $_->{dns} } @devices });

    var(links => {});
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
        var('links')->{ $l->{left_ip} } ||= [];
        push @{ var('links')->{ $l->{left_ip} } }, $l->{right_ip};
    }

    my %tree = (
        ip => $start,
        name => _get_name($start),
        fullname => (var('devices')->{$start} || $start),
        children => [],
    );

    var(seen => {$start => 1});
    my $max = _add_children($tree{children}, var('links')->{$start}, 1, $depth);
    $tree{scale} = $max;

    content_type('application/json');
    to_json(\%tree);
};

ajax '/ajax/data/device/alldevicelinks' => require_login sub {
    my @devices = schema('netdisco')->resultset('Device')->search({}, {
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
      columns => ['ip', 'dns'],
    })->all;
    var(devices => { map { $_->{ip} => $_->{dns} } @devices });

    my $rs = schema('netdisco')->resultset('Virtual::DeviceLinks')->search({}, {
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    });

    my %tree = ();
    while (my $l = $rs->next) {
        push @{ $tree{ _get_name($l->{left_ip} )} },
          _get_name($l->{right_ip});
    }

    content_type('application/json');
    to_json(\%tree);
};

true;
