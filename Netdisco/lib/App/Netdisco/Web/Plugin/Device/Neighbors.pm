package App::Netdisco::Web::Plugin::Device::Neighbors;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use NetAddr::IP::Lite ':lower';

use App::Netdisco::Web::Plugin;

register_device_tab({ id => 'netmap', label => 'Neighbors' });

ajax '/ajax/content/device/netmap' => sub {
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
    my ($ptr, $childs) = @_;
    my @legit = ();

    foreach my $c (@$childs) {
        next if exists var('seen')->{$c};
        var('seen')->{$c}++;
        push @legit, $c;
        push @{$ptr}, { name => _get_name($c), ip => $c };
    }

    for (my $i = 0; $i < @legit; $i++) {
        $ptr->[$i]->{children} = [];
        _add_children($ptr->[$i]->{children}, var('links')->{$legit[$i]});
    }
}

# d3 seems not to use proper ajax semantics, so get instead of ajax
get '/ajax/data/device/netmap' => sub {
    my $ip = NetAddr::IP::Lite->new(param('q'));
    return unless $ip;
    my $start = $ip->addr;

    my @devices = schema('netdisco')->resultset('Device')->search({}, {
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
      columns => ['ip', 'dns'],
    })->all;
    var(devices => { map { $_->{ip} => $_->{dns} } @devices });

    var(links => {});
    my $rs = schema('netdisco')->resultset('Virtual::DeviceLinks')->search({}, {
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    });

    while (my $l = $rs->next) {
        var('links')->{ $l->{left_ip} } ||= [];
        push @{ var('links')->{ $l->{left_ip} } }, $l->{right_ip};
    }

    my %tree = (
        ip => $start,
        name => _get_name($start),
        children => [],
    );

    var(seen => {$start => 1});
    _add_children($tree{children}, var('links')->{$start});

    content_type('application/json');
    return to_json(\%tree);
};

ajax '/ajax/data/device/alldevicelinks' => sub {
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
    return to_json(\%tree);
};

true;
