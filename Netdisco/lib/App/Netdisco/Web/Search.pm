package App::Netdisco::Web::Search;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use NetAddr::IP::Lite ':lower';
use Net::MAC ();
use List::MoreUtils ();

hook 'before' => sub {
    # view settings for node options
    var('node_options' => [
      { name => 'stamps', label => 'Time Stamps', default => 'on' },
    ]);
    # view settings for device options
    var('device_options' => [
      { name => 'matchall', label => 'Match All Options', default => 'on' },
    ]);

    # new searches will use these defaults in their sidebars
    var('search_node'   => uri_for('/search', {tab => 'node'}));
    var('search_device' => uri_for('/search', {tab => 'device'}));

    foreach my $col (@{ var('node_options') }) {
        next unless $col->{default} eq 'on';
        var('search_node')->query_param($col->{name}, 'checked');
    }

    foreach my $col (@{ var('device_options') }) {
        next unless $col->{default} eq 'on';
        var('search_device')->query_param($col->{name}, 'checked');
    }

    if (request->path eq uri_for('/search')->path
        or index(request->path, uri_for('/ajax/content/search')->path) == 0) {

        foreach my $col (@{ var('node_options') }) {
            next unless $col->{default} eq 'on';
            params->{$col->{name}} = 'checked'
              if not param('tab') or param('tab') ne 'node';
        }

        foreach my $col (@{ var('device_options') }) {
            next unless $col->{default} eq 'on';
            params->{$col->{name}} = 'checked'
              if not param('tab') or param('tab') ne 'device';
        }

        # used in the device search sidebar template to set selected items
        foreach my $opt (qw/model vendor os_ver/) {
            my $p = (ref [] eq ref param($opt) ? param($opt)
                                               : (param($opt) ? [param($opt)] : []));
            var("${opt}_lkp" => { map { $_ => 1 } @$p });
        }
    }
};

# device with various properties or a default match-all
ajax '/ajax/content/search/device' => sub {
    my $has_opt = List::MoreUtils::any {param($_)}
      qw/name location dns ip description model os_ver vendor/;
    my $set;

    if ($has_opt) {
        $set = schema('netdisco')->resultset('Device')->search_by_field(scalar params);
    }
    else {
        my $q = param('q');
        return unless $q;

        $set = schema('netdisco')->resultset('Device')->search_fuzzy($q);
    }
    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/device.tt', {
      results => $set,
    }, { layout => undef };
};

# nodes matching the param as an IP or DNS hostname or MAC
ajax '/ajax/content/search/node' => sub {
    my $node = param('q');
    return unless $node;
    content_type('text/html');

    my $mac = Net::MAC->new(mac => $node, 'die' => 0, verbose => 0);
    my @active = (param('archived') ? () : (-bool => 'active'));

    if (! $mac->get_error) {
        my $sightings = schema('netdisco')->resultset('Node')
          ->search_by_mac({mac => $mac->as_IEEE, @active});

        my $ips = schema('netdisco')->resultset('NodeIp')
          ->search_by_mac({mac => $mac->as_IEEE, @active});

        my $ports = schema('netdisco')->resultset('DevicePort')
          ->search({mac => $mac->as_IEEE});

        return unless $sightings->count
            or $ips->count
            or $ports->count;

        template 'ajax/search/node_by_mac.tt', {
          ips => $ips,
          sightings => $sightings,
          ports => $ports,
        }, { layout => undef };
    }
    else {
        my $set;

        if (my $ip = NetAddr::IP::Lite->new($node)) {
            # search_by_ip() will extract cidr notation if necessary
            $set = schema('netdisco')->resultset('NodeIp')
              ->search_by_ip({ip => $ip, @active});
        }
        else {
            if (param('partial')) {
                $node = "\%$node\%";
            }
            elsif (setting('domain_suffix')) {
                $node .= setting('domain_suffix')
                    if index($node, setting('domain_suffix')) == -1;
            }
            $set = schema('netdisco')->resultset('NodeIp')
              ->search_by_dns({dns => $node, @active});
        }
        return unless $set and $set->count;

        template 'ajax/search/node_by_ip.tt', {
          macs => $set,
          archive_filter => {@active},
        }, { layout => undef };
    }
};

# devices carrying vlan xxx
ajax '/ajax/content/search/vlan' => sub {
    my $q = param('q');
    return unless $q;
    my $set;

    if ($q =~ m/^\d+$/) {
        $set = schema('netdisco')->resultset('Device')->carrying_vlan({vlan => $q});
    }
    else {
        $set = schema('netdisco')->resultset('Device')->carrying_vlan_name({name => $q});
    }
    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/vlan.tt', {
      results => $set,
    }, { layout => undef };
};

# device ports with a description (er, name) matching
ajax '/ajax/content/search/port' => sub {
    my $q = param('q');
    return unless $q;
    my $set;

    if ($q =~ m/^\d+$/) {
        $set = schema('netdisco')->resultset('DevicePort')->search({vlan => $q});
    }
    else {
        $set = schema('netdisco')->resultset('DevicePort')->search({name => $q});
    }
    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/port.tt', {
      results => $set,
    }, { layout => undef };
};

get '/search' => sub {
    my $q = param('q');
    if (not param('tab')) {
        if (not $q) {
            redirect uri_for('/');
        }

        # pick most likely tab for initial results
        if ($q =~ m/^\d+$/) {
            params->{'tab'} = 'vlan';
        }
        else {
            my $s = schema('netdisco');
            if ($q =~ m{^[a-f0-9.:/]+$}i) {
                my $ip = NetAddr::IP::Lite->new($q);
                my $nd = $s->resultset('Device')->search_by_field({ip => $q});
                if ($ip and $nd->count) {
                    if ($nd->count == 1) {
                        # redirect to device details for the one device
                        redirect uri_for('/device',
                          {tab => 'details', q => $q, f => ''});
                    }
                    params->{'tab'} = 'device';
                }
                else {
                    # this will match for MAC addresses
                    # and partial IPs (subnets?)
                    params->{'tab'} = 'node';
                }
            }
            else {
                my $nd = $s->resultset('Device')->search({dns => { '-ilike' => "\%$q\%" }});
                if ($nd->count) {
                    if ($nd->count == 1) {
                        # redirect to device details for the one device
                        redirect uri_for('/device',
                          {tab => 'details', q => $nd->first->ip, f => ''});
                    }
                    params->{'tab'} = 'device';
                }
                elsif ($s->resultset('DevicePort')
                         ->search({name => "\%$q\%"})->count) {
                    params->{'tab'} = 'port';
                }
            }
            params->{'tab'} ||= 'node';
        }
    }

    # used in the device search sidebar to populate select inputs
    var('model_list' => [
      schema('netdisco')->resultset('Device')->get_distinct_col('model')
    ]);
    var('os_ver_list' => [
      schema('netdisco')->resultset('Device')->get_distinct_col('os_ver')
    ]);
    var('vendor_list' => [
      schema('netdisco')->resultset('Device')->get_distinct_col('vendor')
    ]);

    # list of tabs
    var('tabs' => [
        { id => 'device', label => 'Device' },
        { id => 'node',   label => 'Node'   },
        { id => 'vlan',   label => 'VLAN'   },
        { id => 'port',   label => 'Port'   },
    ]);

    template 'search';
};

true;
