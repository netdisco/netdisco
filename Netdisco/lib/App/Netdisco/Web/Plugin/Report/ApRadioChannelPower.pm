package App::Netdisco::Web::Plugin::Report::ApRadioChannelPower;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category => 'Wireless',
        tag      => 'apradiochannelpower',
        label    => 'Access Point Radios Channel and Power',
    }
);

sub port_tree {
    my $devices = shift;

    my %ports;

    foreach my $device (@$devices) {
        my $power2;

        if ( defined( $device->power ) && $device->power ) {
            $power2 = sprintf( "%.1f",
                10.0 * CORE::log( $device->power ) / CORE::log(10) );
        }

        $ports{ $device->device_name }{device} = {
            name     => $device->device_name,
            ip       => $device->ip,
            dns      => $device->dns,
            model    => $device->model,
            location => $device->location
        };
        push @{ $ports{ $device->device_name }{ports} },
            {
            port    => $device->port,
            name    => $device->port_name,
            descr   => $device->descr,
            channel => $device->channel,
            power   => $device->power,
            power2  => $power2
            };
    }
    return \%ports;
}

ajax '/ajax/content/report/apradiochannelpower' => require_login sub {
    my @set
        = schema('netdisco')->resultset('Virtual::ApRadioChannelPower')->all;

    my $results = port_tree( \@set );
    return unless scalar %$results;

    content_type('text/html');
    template 'ajax/report/apradiochannelpower.tt', { results => $results, },
        { layout => undef };
};

true;
