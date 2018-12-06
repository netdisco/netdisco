package App::Netdisco::Web::AuthN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

hook 'before' => sub {
    params->{return_url} ||= ((request->path ne uri_for('/')->path)
      ? request->uri : uri_for('/inventory')->path);

    # from the internals of Dancer::Plugin::Auth::Extensible
    my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');

    if (! session('logged_in_user') && request->path ne uri_for('/login')->path) {
        if (setting('trust_x_remote_user')
          and scalar request->header('X-REMOTE_USER')
          and length scalar request->header('X-REMOTE_USER')) {

            (my $user = scalar request->header('X-REMOTE_USER')) =~ s/@[^@]*$//;
            return if setting('validate_remote_user')
              and not $provider->get_user_details($user);

            session(logged_in_user => $user);
            session(logged_in_user_realm => 'users');
        }
        elsif (setting('trust_remote_user')
          and defined $ENV{REMOTE_USER}
          and length  $ENV{REMOTE_USER}) {

            (my $user = $ENV{REMOTE_USER}) =~ s/@[^@]*$//;
            return if setting('validate_remote_user')
              and not $provider->get_user_details($user);

            session(logged_in_user => $user);
            session(logged_in_user_realm => 'users');
        }
        elsif (setting('no_auth')) {
            session(logged_in_user => 'guest');
            session(logged_in_user_realm => 'users');
        }
        else {
            # user has no AuthN - force to handler for '/'
            request->path_info('/');
        }
    }
};

get qr{^/(?:login(?:/denied)?)?} => sub {
    template 'index', { return_url => param('return_url') };
};

# override default login_handler so we can log access in the database
post '/login' => sub {
    my $mode = (request->is_ajax ? 'API' : 'Web');
    my ($success, $realm) = authenticate_user(
        param('username'), param('password')
    );

    if ($success) {
        my $user = schema('netdisco')->resultset('User')
          ->find({ username => { -ilike => quotemeta(param('username')) } });

        session logged_in_user => $user->username;
        session logged_in_fullname => $user->fullname;
        session logged_in_user_realm => $realm;

        schema('netdisco')->resultset('UserLog')->create({
          username => session('logged_in_user'),
          userip => request->remote_address,
          event => "Login ($mode)",
          details => param('return_url'),
        });

        $user->update({ last_on => \'now()' });

        return if request->is_ajax;
        redirect param('return_url');
    }
    else {
        session->destroy;

        schema('netdisco')->resultset('UserLog')->create({
          username => param('username'),
          userip => request->remote_address,
          event => "Login Failure ($mode)",
          details => param('return_url'),
        });

        if (request->is_ajax) {
            status('unauthorized');
        }
        else {
            vars->{login_failed}++;
            forward uri_for('/login'),
              { login_failed => 1, return_url => param('return_url') },
              { method => 'GET' };
        }
    }
};

# we override the default login_handler, so logout has to be handled as well
any ['get', 'post'] => '/logout' => sub {
    schema('netdisco')->resultset('UserLog')->create({
      username => session('logged_in_user'),
      userip => request->remote_address,
      event => "Logout",
      details => '',
    });

    session->destroy;
    redirect uri_for('/inventory')->path;
};

true;
