package Netdisco;

use Dancer ':syntax';
use Dancer::Plugin::Database;
use Digest::MD5 ();

hook 'before' => sub {
    if (! session('user') && request->path !~ m{^/login}) {
        var(requested_path => request->path);
        request->path_info('/');
    }
};

get '/' => sub {
    template 'index';
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
    redirect '/?notfound=1';
};

true;
