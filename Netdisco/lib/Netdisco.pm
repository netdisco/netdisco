package Netdisco;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::Database;
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
    return '<p>Hello World.</p>';
};

get '/search' => sub {
    my $q = param('q');
    if ($q and not param('tab')) {
        # pick most likely tab for initial results
        if ($q =~ m/^\d+$/) {
            params->{'tab'} = 'vlan';
        }
        else {
            params->{'tab'} = 'device';
        }
    }
    elsif (not $q) {
        redirect '/';
        return;
    }

    # set up default search options for each type
    if (param('tab') and param('tab') ne 'node') {
        params->{'stamps'} = 'checked';
        params->{'vendor'} = 'checked';
    }

    template 'search';
};

post '/login' => sub {
    if (param('username') and param('password')) {
        my $user = database->quick_select('users',
           { username => param('username') }
        );
        if ($user) {
            my $sum = Digest::MD5::md5_hex(param('password'));
            if ($sum and $sum eq $user->{password}) {
                session(user => $user->{username});
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
