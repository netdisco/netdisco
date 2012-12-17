package App::Netdisco::Web::AuthN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use Digest::MD5 ();

hook 'before' => sub {
    if (! session('user') && request->path ne uri_for('/login')->path) {
        if (setting('no_auth')) {
            session(user => 'guest');
        }
        else {
            request->path_info('/');
        }
    }

    if (session('user') && session->id) {
        var(user => schema('netdisco')->resultset('User')
                                      ->find(session('user')));
    }
};

post '/login' => sub {
    if (param('username') and param('password')) {
        my $user = schema('netdisco')->resultset('User')->find(param('username'));
        if ($user) {
            my $sum = Digest::MD5::md5_hex(param('password'));
            if ($sum and $sum eq $user->password) {
                session(user => $user->username);
                redirect uri_for('/inventory');
                return;
            }
        }
    }
    redirect uri_for('/', {failed => 1});
};

get '/logout' => sub {
    session->destroy;
    redirect uri_for('/', {logout => 1});
};

true;
