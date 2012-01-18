package Netdisco::Web::AuthN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use Digest::MD5 ();

hook 'before' => sub {
    if (! session('user') && request->path !~ m{/login$}) {
        if (setting('environment') eq 'development' and setting('no_auth')) {
            session(user => 'developer');
        }
        else {
            var(requested_path => request->path);
            request->path_info('/');
        }
    }
    # use Data::Dumper;
    # Dancer::Logger:core( Dumper request );
};

post '/login' => sub {
    if (param('username') and param('password')) {
        my $user = schema('netdisco')->resultset('User')->find(param('username'));
        if ($user) {
            my $sum = Digest::MD5::md5_hex(param('password'));
            if ($sum and $sum eq $user->password) {
                session(user => $user->username);
                # session(host => request->header('x-forwarded-for'));
                # redirect param('path') || '/'; FIXME requested_path?
                redirect uri_for('/');
                return;
            }
        }
    }
    redirect '/?failed=1';
};

get '/logout' => sub {
    session->destroy;
    redirect uri_for('/', {logout => 1});
};

true;
