package Netdisco::Web::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use NetAddr::IP::Lite ':lower';
use netdisco (); # for sort_port

hook 'before' => sub {
    # list of port detail columns
    var('port_columns' => [
        { name => 'c_port',        label => 'Port',              default => 'on' },
        { name => 'c_descr',       label => 'Description',       default => ''   },
        { name => 'c_type',        label => 'Type',              default => ''   },
        { name => 'c_duplex',      label => 'Duplex',            default => ''   },
        { name => 'c_lastchange',  label => 'Last Change',       default => ''   },
        { name => 'c_name',        label => 'Name',              default => 'on' },
        { name => 'c_speed',       label => 'Speed',             default => ''   },
        { name => 'c_mac',         label => 'Port MAC',          default => ''   },
        { name => 'c_mtu',         label => 'MTU',               default => ''   },
        { name => 'c_vlan',        label => 'Native VLAN',       default => 'on' },
        { name => 'c_vmember',     label => 'VLAN Membership',   default => 'on' },
        { name => 'c_connected',   label => 'Connected Devices', default => 'on' },
        { name => 'c_stp',         label => 'Spanning Tree',     default => ''   },
        { name => 'c_up',          label => 'Status',            default => ''   },
    ]);

    # view settings for port connected devices
    var('connected_properties' => [
        { name => 'n_age',      label => 'Age Stamp',     default => ''   },
        { name => 'n_ip',       label => 'IP Address',    default => 'on' },
        { name => 'n_archived', label => 'Archived Data', default => ''   },
    ]);

    # set up default search options for each type
    if (request->path =~ m{/device$}) {
        if (not param('tab') or param('tab') ne 'ports' or scalar keys %{params()} < 4) {
            foreach my $col (@{ var('port_columns') }) {
                params->{$col->{name}} = 'checked' if $col->{default} eq 'on';
            }
            foreach my $col (@{ var('connected_properties') }) {
                params->{$col->{name}} = 'checked' if $col->{default} eq 'on';
            }
            params->{'age_num'} = 3;
            params->{'age_unit'} = 'months';
        }
    }
};

ajax '/ajax/content/device/:thing' => sub {
    return "<p>Hello, this is where the ". param('thing') ." content goes.</p>";
};

# device interface addresses
ajax '/ajax/content/device/addresses' => sub {
    my $ip = param('ip');
    return unless $ip;

    my $set = schema('netdisco')->resultset('DeviceIp')->search({ip => $ip}, { order_by => 'alias' });
    return unless $set->count;

    content_type('text/html');
    template 'ajax/device/addresses.tt', {
      results => $set,
    }, { layout => undef };
};

# device ports with a description (er, name) matching
ajax '/ajax/content/device/ports' => sub {
    my $ip = param('ip');
    return unless $ip;

    my $set = schema('netdisco')->resultset('DevicePort')->by_ip($ip);

    # refine by ports if requested
    my $q = param('q');
    if ($q) {
        if ($q =~ m/^\d+$/) {
            $set = $set->by_vlan($q);
        }
        else {
            my $c = schema('netdisco')->resultset('DevicePort')->by_ip($ip)->by_port($q);
            if ($c->count) {
                $set = $set->by_port($q);
            }
            else {
                $set = $set->by_name($q);
            }
        }
    }
    return unless $set->count;

    # sort, and filter by free ports
    # the filter could be in the template but here allows a 'no records' msg
    my $results = [ sort { &netdisco::sort_port($a->port, $b->port) }
                    grep { not param('free')
                           or $_->is_free(param('age_num'), param('age_unit')) } $set->all ];

    return unless scalar @$results;

    content_type('text/html');
    template 'ajax/device/ports.tt', {
      results => $results,
    }, { layout => undef };
};

# device details table
ajax '/ajax/content/device/details' => sub {
    my $ip = param('ip');
    return unless $ip;

    my $device = schema('netdisco')->resultset('Device')->find($ip);
    return unless $device;

    content_type('text/html');
    template 'ajax/device/details.tt', {
      d => $device,
    }, { layout => undef };
};

get '/device' => sub {
    my $ip = NetAddr::IP::Lite->new(param('ip'));
    if (! $ip) {
        redirect uri_for('/', {nosuchdevice => 1});
        return;
    }

    my $device = schema('netdisco')->resultset('Device')->find($ip->addr);
    if (! $device) {
        redirect uri_for('/', {nosuchdevice => 1});
        return;
    }

    # list of tabs
    var('tabs' => [
        { id => 'details',   label => 'Details'   },
        { id => 'ports',     label => 'Ports'     },
        { id => 'modules',   label => 'Modules'   },
        { id => 'addresses', label => 'Addresses' },
    ]);

    params->{'tab'} ||= 'details';
    template 'device', { d => $device };
};

true;
