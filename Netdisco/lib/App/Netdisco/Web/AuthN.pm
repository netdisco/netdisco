package App::Netdisco::Web::AuthN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

hook 'before' => sub {
    params->{return_url} ||= '/inventory';

    if (! session('logged_in_user') && request->path ne uri_for('/login')->path) {
        if (setting('trust_x_remote_user') and scalar request->header('X-REMOTE_USER')) {
            session(logged_in_user => scalar request->header('X-REMOTE_USER'));
        }
        elsif (setting('trust_remote_user') and $ENV{REMOTE_USER}) {
            session(logged_in_user => $ENV{REMOTE_USER});
        }
        elsif (setting('no_auth')) {
            session(logged_in_user => 'guest');
        }
        else {
            # user has no AuthN - force to handler for '/'
            request->path_info('/');
        }
    }
};

true;
