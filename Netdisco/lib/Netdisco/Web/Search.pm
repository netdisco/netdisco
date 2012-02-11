package Netdisco::Web::Search;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use NetAddr::IP::Lite ':lower';
use Net::MAC ();
use List::MoreUtils ();
use Net::DNS ();

hook 'before' => sub {
    # make hash lookups of query lists
    foreach my $opt (qw/model vendor os_ver/) {
        my $p = (ref [] eq ref param($opt) ? param($opt) : (param($opt) ? [param($opt)] : []));
        var("${opt}_lkp" => { map { $_ => 1 } @$p });
    }

    # set up default search options for each type
    if (request->path =~ m{/search$}) {
        if (not param('tab') or param('tab') ne 'node') {
            params->{'stamps'} = 'checked';
        }
        if (not param('tab') or param('tab') ne 'device') {
            params->{'matchall'} = 'checked';
        }
    }

    # set up query string defaults for hyperlinks to templates with forms
    var('query_defaults' => { map { ($_ => "tab=$_") } qw/node device/ });

    var('query_defaults')->{node} .= "\&$_=". (param($_) || '')
      for qw/stamps vendor archived partial/;
    var('query_defaults')->{device} .= "\&$_=". (param($_) || '')
      for qw/matchall/;
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
    my @active = (param('archived') ? () : (active => 1));

    if (eval { $mac->as_IEEE }) {

        my $sightings = schema('netdisco')->resultset('Node')
          ->search_by_mac({mac => $mac->as_IEEE, @active});

        my $ips = schema('netdisco')->resultset('NodeIp')
          ->search_by_mac({mac => $mac->as_IEEE, @active});

        my $ports = schema('netdisco')->resultset('DevicePort')
          ->search_by_mac({mac => $mac->as_IEEE});

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
            if (schema('netdisco')->resultset('NodeIp')->has_dns_col) {
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
            elsif (setting('domain_suffix')) {
                $node .= setting('domain_suffix')
                    if index($node, setting('domain_suffix')) == -1;
                my $q = Net::DNS::Resolver->new->query($node);
                if ($q) {
                    foreach my $rr ($q->answer) {
                        next unless $rr->type eq 'A';
                        $node = $rr->address;
                    }
                }
                else {
                    return;
                }
                $set = schema('netdisco')->resultset('NodeIp')
                  ->search_by_ip({ip => $node, @active});
            }
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
        $set = schema('netdisco')->resultset('DevicePort')->search_by_vlan({vlan => $q});
    }
    else {
        $set = schema('netdisco')->resultset('DevicePort')->search_by_name({name => $q});
    }
    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/port.tt', {
      results => $set,
    }, { layout => undef };
};

get '/search' => sub {
    # set up property lists for device search
    var('model_list' => [
      schema('netdisco')->resultset('Device')->get_distinct('model')
    ]);
    var('os_ver_list' => [
      schema('netdisco')->resultset('Device')->get_distinct('os_ver')
    ]);
    var('vendor_list' => [
      schema('netdisco')->resultset('Device')->get_distinct('vendor')
    ]);

    params->{'q'} ||= '_'; # FIXME a cheat Inventory, for now

    my $q = param('q');
    if ($q and not param('tab')) {
        # pick most likely tab for initial results
        if ($q =~ m/^\d+$/) {
            params->{'tab'} = 'vlan';
        }
        else {
            my $s = schema('netdisco');
            if ($q =~ m{^[a-f0-9.:/]+$}i) {
                if (NetAddr::IP::Lite->new($q) and
                    $s->resultset('Device')->find($q)) {
                    params->{'tab'} = 'device';
                }
                else {
                    # this will match for MAC addresses
                    # and partial IPs (subnets?)
                    params->{'tab'} = 'node';
                }
            }
            else {
                if ($s->resultset('Device')
                      ->search({dns => { '-ilike' => "\%$q\%" }})->count) {
                    params->{'tab'} = 'device';
                }
                elsif ($s->resultset('DevicePort')
                         ->search_by_name({name => "\%$q\%"})->count) {
                    params->{'tab'} = 'port';
                }
            }
            params->{'tab'} ||= 'node';
        }
    }

    # list of tabs
    var('tabs' => [
        { id => 'device', label => 'Device' },
        { id => 'node',   label => 'Node'   },
        { id => 'vlan',   label => 'VLAN'   },
        { id => 'port',   label => 'Port'   },
    ]);

    var('node_ip_has_dns_col' =>
      schema('netdisco')->resultset('NodeIp')->has_dns_col);

    template 'search';
};

true;
