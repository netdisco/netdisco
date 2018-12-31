package App::Netdisco::Web::AuthN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use MIME::Base64;

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
        elsif (setting('api_token_lifetime')
          and (index(request->path,uri_for('/api/')->path) == 0
           or request->path eq uri_for('/swagger.json')->path)) {

            my $token = request->header('Authorization');
            my $user = $provider->validate_api_token($token)
              or return;

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
    if (param('return_url') and param('return_url') =~ m{^/api/}) {
      status 403;
      return to_json {
        error => 'not authorized',
        return_url => param('return_url'),
      };
    }
    else {
      template 'index', { return_url => param('return_url') };
    }
};

# override default login_handler so we can log access in the database
post '/login' => sub {
    my $mode = (request->is_ajax ? 'WebData'
                                 : request->header('Authorization') ? 'API'
                                                                    : 'WebUI');
    # get authN data from request (HTTP BasicAuth or URL params)
    my $authheader = request->header('Authorization');
    if (defined $authheader and $authheader =~ /^Basic (.*)$/i) {
        my ($u, $p) = split(m/:/, (MIME::Base64::decode($1) || ":"));
        params->{username} = $u;
        params->{password} = $p;
    }

    # test authN
    my ($success, $realm) = authenticate_user(param('username'),param('password'));

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

        return if $mode eq 'WebData';

        # if API return a token and record its lifetime
        if ($mode eq 'API') {
            $user->update({
              token_from => time,
              token => \'md5(random()::text)',
            })->discard_changes();
            return 'api_key:'. $user->token;
        }

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

        if ($mode ne 'WebUI') {
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
