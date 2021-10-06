package App::Netdisco::Web::AuthN;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Swagger;

use App::Netdisco; # a safe noop but needed for standalone testing
use App::Netdisco::Util::Web 'request_is_api';
use MIME::Base64;

# ensure that regardless of where the user is redirected, we have a link
# back to the page they requested.
hook 'before' => sub {
    params->{return_url} ||= ((request->path ne uri_for('/')->path)
      ? request->uri : uri_for(setting('web_home'))->path);
};

# Dancer will create a session if it sees its own cookie. For the API and also
# various auto login options we need to bootstrap the session instead. If no
# auth data passed, then the hook simply returns, no session is set, and the
# user is redirected to login page.
hook 'before' => sub {
    # return if request is for endpoints not requiring a session
    return if (
      request->path eq uri_for('/login')->path
      or request->path eq uri_for('/logout')->path
      or request->path eq uri_for('/swagger.json')->path
      or index(request->path, uri_for('/swagger-ui')->path) == 0
    );

    # from the internals of Dancer::Plugin::Auth::Extensible
    my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');

    # API calls must conform strictly to path and header requirements
    if (request_is_api) {
        # Dancer will issue a cookie to the client which could be returned and
        # cause API calls to succeed without passing token. Kill the session.
        session->destroy;

        my $token = request->header('Authorization');
        my $user = $provider->validate_api_token($token)
          or return;

        session(logged_in_user => $user);
        session(logged_in_user_realm => 'users');
        return;
    }

    # after checking API, we can short circuit if Dancer reads its cookie OK
    return if session('logged_in_user');

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
};

# override default login_handler so we can log access in the database
swagger_path {
  description => 'Obtain an API Key',
  tags => ['General'],
  path => (setting('url_base') ? setting('url_base')->with('/login')->path : '/login'),
  parameters => [],
  responses => { default => { examples => {
    'application/json' => { api_key => 'cc9d5c02d8898e5728b7d7a0339c0785' } } },
  },
},
post '/login' => sub {
    my $api = ((request->accept and request->accept =~ m/(?:json|javascript)/) ? true : false);

    # get authN data from BasicAuth header used by API, put into params
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
          event => (sprintf 'Login (%s)', ($api ? 'API' : 'WebUI')),
          details => param('return_url'),
        });
        $user->update({ last_on => \'now()' });

        if ($api) {
            header('Content-Type' => 'application/json');
            $user->update({
              token_from => time,
              token => \'md5(random()::text)',
            })->discard_changes();
            return to_json { api_key => $user->token };
        }

        redirect param('return_url');
    }
    else {
        # invalidate session cookie
        session->destroy;

        schema('netdisco')->resultset('UserLog')->create({
          username => param('username'),
          userip => request->remote_address,
          event => (sprintf 'Login Failure (%s)', ($api ? 'API' : 'WebUI')),
          details => param('return_url'),
        });

        if ($api) {
            header('Content-Type' => 'application/json');
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
# must be after the path is declared, above.
Dancer::Plugin::Swagger->instance->doc
  ->{paths}->{ (setting('url_base') ? setting('url_base')->with('/login')->path : '/login') }
  ->{post}->{security}->[0]->{BasicAuth} = [];

# we override the default login_handler, so logout has to be handled as well
swagger_path {
  description => 'Destroy user API Key and session cookie',
  tags => ['General'],
  path => (setting('url_base') ? setting('url_base')->with('/logout')->path : '/logout'),
  parameters => [],
  responses => { default => { examples => { 'application/json' => {} } } },
},
get '/logout' => sub {
    my $api = ((request->accept and request->accept =~ m/(?:json|javascript)/) ? true : false);

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
      event => (sprintf 'Logout (%s)', ($api ? 'API' : 'WebUI')),
      details => '',
    });

    if ($api) {
        header('Content-Type' => 'application/json');
        return to_json {};
    }

    redirect uri_for(setting('web_home'))->path;
};

# user redirected here (POST -> GET) when login fails
get qr{^/(?:login(?:/denied)?)?} => sub {
    my $api = ((request->accept and request->accept =~ m/(?:json|javascript)/) ? true : false);

    if ($api) {
      header('Content-Type' => 'application/json');
      status('unauthorized');
      return to_json {
        error => 'not authorized',
        return_url => param('return_url'),
      };
    }
    elsif (defined request->header('X-Requested-With')
           and request->header('X-Requested-With') eq 'XMLHttpRequest') {
      status('unauthorized');
      return '<div class="span2 alert alert-error"><i class="icon-ban-circle"></i> Error: unauthorized.</div>';
    }
    else {
      template 'index', {
        return_url => param('return_url')
      }, { layout => 'main' };
    }
};

true;
