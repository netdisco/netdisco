package Netdisco::Web::AuthN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use Digest::MD5 ();

hook 'before' => sub {
    if (! session('user') && request->path !~ m{^/login}) {
        if (setting('environment') eq 'development' and setting('no_auth')) {
            session(user => 'developer');
        }
        else {
            var(requested_path => request->path);
            request->path_info('/');
        }
    }
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

true;
