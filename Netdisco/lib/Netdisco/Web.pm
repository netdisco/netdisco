package Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use Digest::MD5 ();
use Socket6 (); # to ensure dependency is met
use HTML::Entities (); # to ensure dependency is met
use NetAddr::IP::Lite ':lower';
use Net::MAC ();
use List::MoreUtils ();

hook 'before' => sub {
    if (! session('user') && request->path !~ m{^/login}) {
        if (setting('environment') eq 'development') {
            session(user => 'developer');
        }
        else {
            var(requested_path => request->path);
            request->path_info('/');
        }
    }

    # make hash lookups of query lists
    foreach my $opt (qw/model vendor os_ver/) {
        my $p = (ref '' eq ref param($opt) ? [param($opt)] : param($opt));
        var("${opt}_lkp" => { map { $_ => 1 } @$p });
    }

    # set up default search options for each type
    if (not param('tab') or param('tab') ne 'node') {
        params->{'stamps'} = 'checked';
    }
    if (not param('tab') or param('tab') ne 'device') {
        params->{'matchall'} = 'checked';
    }

    # set up query string defaults for hyperlinks to templates with forms
    var('query_defaults' => { map { ($_ => "tab=$_") } qw/node device/ });

    var('query_defaults')->{node} .= "\&$_=". (param($_) || '')
      for qw/stamps vendor archived partial/;
    var('query_defaults')->{device} .= "\&$_=". (param($_) || '')
      for qw/matchall/;
};

ajax '/ajax/content/device/:thing' => sub {
    return "<p>Hello ". param('thing') ."</p>";
};

# device ports with a description (er, name) matching
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
        redirect '/?nosuchdevice=1';
        return;
    }

    my $device = schema('netdisco')->resultset('Device')->find($ip->addr);
    if (! $device) {
        redirect '/?nosuchdevice=1';
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

# device with various properties or a default match-all
ajax '/ajax/content/search/device' => sub {
    my $has_opt = List::MoreUtils::any {param($_)}
      qw/name location dns ip description model os_ver vendor/;
    my $set;

    if ($has_opt) {
        $set = schema('netdisco')->resultset('Device')->by_field(scalar params);
    }
    else {
        my $q = param('q');
        return unless $q;

        $set = schema('netdisco')->resultset('Device')->by_any($q);
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
    if (eval { $mac->as_IEEE }) {

        my $ips = schema('netdisco')->resultset('NodeIp')
          ->by_mac(param('archived'), $mac->as_IEEE);
        return unless $ips->count;

        my $sightings = schema('netdisco')->resultset('Node')
          ->by_mac(param('archived'), $mac->as_IEEE);

        my $ports = schema('netdisco')->resultset('DevicePort')
          ->by_mac($mac->as_IEEE);

        template 'ajax/search/node_by_mac.tt', {
          ips => $ips,
          sightings => $sightings,
          ports => $ports,
        }, { layout => undef };
    }
    else {
        my $set;

        if (my $ip = NetAddr::IP::Lite->new($node)) {
            # by_ip() will extract cidr notation if necessary
            $set = schema('netdisco')->resultset('NodeIp')
              ->by_ip(param('archived'), $ip);
        }
        else {
            $node = "\%$node\%" if param('partial');
            $set = schema('netdisco')->resultset('NodeIp')
              ->by_name(param('archived'), $node);
        }
        return unless $set->count;

        template 'ajax/search/node_by_ip.tt', {
          results => $set,
        }, { layout => undef };
    }
};

# devices carrying vlan xxx
ajax '/ajax/content/search/vlan' => sub {
    my $vlan = param('q');
    return unless $vlan;
    my $set;

    if ($vlan =~ m/^\d+$/) {
        $set = schema('netdisco')->resultset('Device')->carrying_vlan($vlan);
    }
    else {
        $set = schema('netdisco')->resultset('Device')->carrying_vlan_name($vlan);
    }
    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/vlan.tt', {
      results => $set,
    }, { layout => undef };
};

# device ports with a description (er, name) matching
ajax '/ajax/content/search/port' => sub {
    my $name = param('q');
    return unless $name;

    my $set = schema('netdisco')->resultset('DevicePort')->by_name($name);
    return unless $set->count;

    content_type('text/html');
    template 'ajax/search/port.tt', {
      results => $set,
    }, { layout => undef };
};

get '/' => sub {
    template 'index';
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

    my $q = param('q');
    if ($q and not param('tab')) {
        # pick most likely tab for initial results
        if ($q =~ m/^\d+$/) {
            params->{'tab'} = 'vlan';
        }
        else {
            my $s = schema('netdisco');
            if ($q =~ m/^[a-f0-9.:]+$/i) {
                if ($s->resultset('Device')->find($q)) {
                    params->{'tab'} = 'device';
                }
                else {
                    # this will match for MAC addresses
                    # and partial IPs (subnets?)
                    params->{'tab'} = 'node';
                }
            }
            else {
                if ($s->resultset('Device')->search({
                  dns => { '-ilike' => "\%$q\%" },
                })->count) {
                    params->{'tab'} = 'device';
                }
                elsif ($s->resultset('NodeIp')->search({
                  dns => { '-ilike' => "\%$q\%" },
                })->count) {
                    params->{'tab'} = 'node';
                }
                elsif ($s->resultset('DevicePort')->search({
                  name => { '-ilike' => "\%$q\%" },
                })->count) {
                    params->{'tab'} = 'port';
                }
            }
            params->{'tab'} ||= 'device';
        }
    }
    elsif (not $q) {
        redirect '/';
        return;
    }

    # list of tabs
    var('tabs' => [
        { id => 'device', label => 'Device' },
        { id => 'node',   label => 'Node'   },
        { id => 'vlan',   label => 'VLAN'   },
        { id => 'port',   label => 'Port'   },
    ]);

    template 'search';
};

post '/login' => sub {
    if (param('username') and param('password')) {
        my $user = schema('netdisco')->resultset('User')->find(param('username'));
        if ($user) {
            my $sum = Digest::MD5::md5_hex(param('password'));
            if ($sum and $sum eq $user->password) {
                session(user => $user->username);
                redirect param('path') || '/';
                return;
            }
        }
    }
    redirect '/?failed=1';
};

get '/logout' => sub {
    session->destroy;
    redirect '/?logout=1';
};

any qr{.*} => sub {
    var('notfound' => true);
    status 'not_found';
    template 'index';
};

true;
