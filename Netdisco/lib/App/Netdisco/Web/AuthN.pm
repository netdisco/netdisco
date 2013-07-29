package App::Netdisco::Web::AuthN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use Digest::MD5 ();

hook 'before' => sub {
    if (! session('user') && request->path ne uri_for('/login')->path) {
        if (setting('trust_x_remote_user') and scalar request->header('X-REMOTE_USER')) {
            session(user => scalar request->header('X-REMOTE_USER'));
        }
        elsif (setting('trust_remote_user') and $ENV{REMOTE_USER}) {
            session(user => $ENV{REMOTE_USER});
        }
        elsif (setting('no_auth')) {
            session(user => 'guest');
        }
        else {
            # user has no AuthN - force to handler for '/'
            request->path_info('/');
        }
    }

    if (session('user') && session->id) {
        var(user => schema('netdisco')->resultset('User')
                                      ->find(session('user')));

        # really just for dev work, to quieten the logs
        var('user')->port_control(0)
          if var('user') and setting('no_port_control');
    }
};

post '/login' => sub {
    if (param('username') and param('password')) {
        my $user = schema('netdisco')->resultset('User')
                                     ->find(param('username'));

        if ($user) {
            my $sum = Digest::MD5::md5_hex(param('password'));
            if (($sum and $user->password) and ($sum eq $user->password)) {
                session(user => $user->username);
                return redirect uri_for('/inventory')->as_string;
            }
        }
    }

    redirect uri_for('/', {failed => 1})->as_string;
};

get '/logout' => sub {
    session->destroy;
    redirect uri_for('/', {logout => 1})->as_string;
};

true;
