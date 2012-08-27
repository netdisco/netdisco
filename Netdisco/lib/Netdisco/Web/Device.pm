package Netdisco::Web::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use NetAddr::IP::Lite ':lower';
use Netdisco::Util (); # for sort_port

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

    # new searches will use these defaults in their sidebars
    var('device_ports' => uri_for('/device', {
      tab => 'ports',
      age_num => 3,
      age_unit => 'months',
    }));

    foreach my $col (@{ var('port_columns') }) {
        next unless $col->{default} eq 'on';
        var('device_ports')->query_param($col->{name}, 'checked');
    }

    foreach my $col (@{ var('connected_properties') }) {
        next unless $col->{default} eq 'on';
        var('device_ports')->query_param($col->{name}, 'checked');
    }

    if (request->path eq uri_for('/device')->path
        or index(request->path, uri_for('/ajax/content/device')->path) == 0) {

        foreach my $col (@{ var('port_columns') }) {
            next unless $col->{default} eq 'on';
            params->{$col->{name}} = 'checked'
              if not param('tab') or param('tab') ne 'ports';
        }

        foreach my $col (@{ var('connected_properties') }) {
            next unless $col->{default} eq 'on';
            params->{$col->{name}} = 'checked'
              if not param('tab') or param('tab') ne 'ports';
        }

        if (not param('tab') or param('tab') ne 'ports') {
            params->{'age_num'} = 3;
            params->{'age_unit'} = 'months';
        }

        # for templates to link to same page with modified query but same options
        my $self_uri = uri_for(request->path, scalar params);
        $self_uri->query_param_delete('q');
        $self_uri->query_param_delete('f');
        var('self_options' => $self_uri->query_form_hash);
    }
};

ajax '/ajax/content/device/:thing' => sub {
    return "<p>Hello, this is where the ". param('thing') ." content goes.</p>";
};

# device interface addresses
ajax '/ajax/content/device/addresses' => sub {
    my $ip = param('q');
    return unless $ip;

    my $set = schema('netdisco')->resultset('DeviceIp')
                ->search({ip => $ip}, {order_by => 'alias'});
    return unless $set->count;

    content_type('text/html');
    template 'ajax/device/addresses.tt', {
      results => $set,
    }, { layout => undef };
};

# device ports with a description (er, name) matching
ajax '/ajax/content/device/ports' => sub {
    my $ip = param('q');
    return unless $ip;

    my $set = schema('netdisco')->resultset('DevicePort')
                ->search({'me.ip' => $ip});

    # refine by ports if requested
    my $q = param('f');
    if ($q) {
        if ($q =~ m/^\d+$/) {
            $set = $set->search({'me.vlan' => $q});
            return unless $set->count;
        }
        else {
            $q =~ s/\*/%/g if index($q, '*') >= 0;
            $q =~ s/\?/_/g if index($q, '?') >= 0;
            $q = { '-ilike' => $q };

            if ($set->search({'me.port' => $q})->count) {
                $set = $set->search({'me.port' => $q});
            }
            else {
                $set = $set->search({'me.name' => $q});
                return unless $set->count;
            }
        }
    }

    # filter for free ports if asked
    my $free_filter = (param('free') ? 'only_free_ports' : 'with_is_free');
    $set = $set->$free_filter({
      age_num => (param('age_num') || 3),
      age_unit => (param('age_unit') || 'months')
    });

    # make sure query asks for formatted timestamps when needed
    $set = $set->with_times if param('c_lastchange');

    # get number of vlans on the port to control whether to list them or not
    $set = $set->with_vlan_count if param('c_vmember');

    # what kind of nodes are we interested in?
    my $nodes_name = (param('n_archived') ? 'nodes' : 'active_nodes');
    $nodes_name .= '_with_age' if param('c_connected') and param('n_age');

    # retrieve active/all connected nodes, and device, if asked for
    $set = $set->search_rs({}, {
      prefetch => [{$nodes_name => 'ips'}, {neighbor_alias => 'device'}],
    }) if param('c_connected');

    # sort ports (empty set would be a 'no records' msg)
    my $results = [ sort { &Netdisco::Util::sort_port($a->port, $b->port) } $set->all ];
    return unless scalar @$results;

    content_type('text/html');
    template 'ajax/device/ports.tt', {
      results => $results,
      nodes => $nodes_name,
    }, { layout => undef };
};

# device details table
ajax '/ajax/content/device/details' => sub {
    my $ip = param('q');
    return unless $ip;

    my $device = schema('netdisco')->resultset('Device')
                   ->with_times()->find($ip);
    return unless $device;

    content_type('text/html');
    template 'ajax/device/details.tt', {
      d => $device,
    }, { layout => undef };
};

# support typeahead with simple AJAX query for device names
ajax '/ajax/data/device/typeahead' => sub {
    my $q = param('query');
    my $set = schema('netdisco')->resultset('Device')->search_fuzzy($q);

    content_type 'application/json';
    return to_json [map {$_->dns || $_->name || $_->ip} $set->all];
};

get '/device' => sub {
    my $ip = NetAddr::IP::Lite->new(param('q'));
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
