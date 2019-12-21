package App::Netdisco::Web::AuthN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Swagger;

use MIME::Base64;

sub request_is_api {
  return (setting('api_token_lifetime')
    and request->header('Authorization')
    and request->accept =~ m/(?:json|javascript)/);
}

hook 'before' => sub {
    params->{return_url} ||= ((request->path ne uri_for('/')->path)
      ? request->uri : uri_for(setting('web_home'))->path);

    # from the internals of Dancer::Plugin::Auth::Extensible
    my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');

    if (! session('logged_in_user')
        and request->path ne uri_for('/login')->path
        and request->path ne uri_for('/logout')->path
        and request->path ne uri_for('/swagger.json')->path
        and index(request->path, uri_for('/swagger-ui')->path) != 0) {

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
        elsif (request_is_api()
          and index(request->path, uri_for('/api')->path) == 0) {

            my $token = request->header('Authorization');
            my $user = $provider->validate_api_token($token)
              or return;

            session(logged_in_user => $user);
            session(logged_in_user_realm => 'users');
        }
        else {
            # user has no AuthN - force to handler for '/'
            request->path_info('/');
        }
    }
};

# user redirected here (POST -> GET) when login fails
get qr{^/(?:login(?:/denied)?)?} => sub {
    if (request_is_api()) {
      status('unauthorized');
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
swagger_path {
  description => 'Obtain an API Key using HTTP BasicAuth',
  tags => ['Global'],
  parameters => [],
  responses => {
    default => {
      examples => {
        'application/json' => { api_key => 'cc9d5c02d8898e5728b7d7a0339c0785' } } },
  },
},
post '/login' => sub {
    my $mode = (request_is_api() ? 'API' : 'WebUI');

    # get authN data from request (HTTP BasicAuth or Form params)
    my $authheader = request->header('Authorization');
    if (defined $authheader and $authheader =~ /^Basic (.*)$/i) {
        my ($u, $p) = split(m/:/, (MIME::Base64::decode($1) || ":"));
        params->{username} = $u;
        params->{password} = $p;
    }

    # validate authN
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

        if ($mode eq 'API') {
            $user->update({
              token_from => time,
              token => \'md5(random()::text)',
            })->discard_changes();
            return to_json { api_key => $user->token };
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

        if ($mode eq 'API') {
            status('unauthorized');
            return to_json { error => 'authentication failed' };
        }

        vars->{login_failed}++;
        forward uri_for('/login'),
          { login_failed => 1, return_url => param('return_url') },
          { method => 'GET' };
    }
};

# ugh, *puke*, but D::P::Swagger has no way to set this with swagger_path
# must be after the path is declared, above.
Dancer::Plugin::Swagger->instance->doc->{paths}->{'/login'}
  ->{post}->{security}->[0]->{BasicAuth} = [];

# we override the default login_handler, so logout has to be handled as well
swagger_path {
  description => 'Destroy user API Key and session cookie',
  tags => ['Global'],
  parameters => [],
  responses => { default => { examples => { 'application/json' => {} } } },
},
get '/logout' => sub {
    my $mode = (request_is_api() ? 'API' : 'WebUI');

    # clear out API token
    my $user = schema('netdisco')->resultset('User')
      ->find({ username => session('logged_in_user')});
    $user->update({token => undef, token_from => undef})->discard_changes()
      if $user and $user->in_storage;

    # invalidate session cookie
    session->destroy;

    schema('netdisco')->resultset('UserLog')->create({
      username => session('logged_in_user'),
      userip => request->remote_address,
      event => "Logout ($mode)",
      details => '',
    });

    if ($mode eq 'API') {
        return to_json {};
    }

    redirect uri_for(setting('web_home'))->path;
};

true;
