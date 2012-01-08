package Netdisco::Web;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Digest::MD5 ();

hook 'before' => sub {
    if (! session('user') && request->path !~ m{^/login}) {
        session(user => 'oliver'); # XXX
        #var(requested_path => request->path);
        #request->path_info('/');
    }
};

get '/' => sub {
    template 'index';
};

ajax '/ajax/content/search/:thing' => sub {
    content_type('text/html');
    return '<p>Hello '. param('thing') .'.</p>';
};

# nodes matching the param as an IP or DNS hostname or MAC
ajax '/ajax/content/search/node' => sub {
    my $node = param('q');
    return unless $node;

    my $set = schema('netdisco')->resultset('NodeIp')
      ->by_ip($node, param('archived'));
    return unless $set->count;

    content_type('text/html');
    template 'content/node.tt', {
      results => $set,
    }, { layout => undef };
};

# devices carrying vlan xxx
ajax '/ajax/content/search/vlan' => sub {
    my $vlan = param('q');
    return unless $vlan and $vlan =~ m/^\d+$/;

    my $set = schema('netdisco')->resultset('Device')->carrying_vlan($vlan);
    return unless $set->count;

    content_type('text/html');
    template 'content/vlan.tt', {
      results => $set,
      columns => [
        { key => 'dns', label => 'Device' },
        { key => 'vlan.description', label => 'Description' },
        { key => 'model', label => 'Model' },
        { key => 'os', label => 'OS' },
        { key => 'vendor', label => 'Vendor' },
      ],
      hyperlink => sub {
          my $row = shift;
          return '/device?q='. $row->ip .'&vlan='. $vlan;
      },
    }, { layout => undef };
};

get '/search' => sub {
    # set up default search options for each type
    if (not param('tab') or param('tab') ne 'node') {
        params->{'stamps'} = 'checked';
        params->{'vendor'} = 'checked';
    }

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
