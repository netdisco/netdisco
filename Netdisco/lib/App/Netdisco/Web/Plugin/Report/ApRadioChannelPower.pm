package App::Netdisco::Web::Plugin::Report::ApRadioChannelPower;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_report(
    {   category => 'Wireless',
        tag      => 'apradiochannelpower',
        label    => 'Access Point Radios Channel and Power',
        provides_csv => 1,
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

get '/ajax/content/report/apradiochannelpower' => require_login sub {
    my @set
        = schema('netdisco')->resultset('Virtual::ApRadioChannelPower')->all;

    my $results = port_tree( \@set );
    return unless scalar %$results;

    if (request->is_ajax) {
    template 'ajax/report/apradiochannelpower.tt', { results => $results, },
        { layout => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/report/apradiochannelpower_csv.tt', { results => $results, },
            { layout => undef };
    }
};

true;
