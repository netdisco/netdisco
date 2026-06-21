package App::Netdisco::Web::API::User;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use Try::Tiny;

swagger_path {
  tags => ['User'],
  path => (setting('api_base') || '').'/users',
  description => 'List all users with their roles and token status',
  responses => { default => {} },
}, get '/api/v1/users' => require_role api_admin => sub {
  header('Content-Type' => 'application/json');

  my @users = schema(vars->{'tenant'})->resultset('User')->search(undef, {
    '+columns' => { token_hint => \"right(token, 8)" },
    order_by => 'username',
  })->hri->all;

  my @result = map {{
    username        => $_->{username},
    fullname        => $_->{fullname},
    note            => $_->{note},
    admin           => $_->{admin}  ? \1 : \0,
    port_control    => $_->{port_control} ? \1 : \0,
    ldap            => $_->{ldap}   ? \1 : \0,
    radius          => $_->{radius} ? \1 : \0,
    tacacs          => $_->{tacacs} ? \1 : \0,
    token_auth_only => $_->{token_auth_only} ? \1 : \0,
    token_hint      => $_->{token_hint},
    token_permanent => $_->{token_no_expire} ? \1 : \0,
    token_allowed_ips => $_->{token_allowed_ips} || [],
    last_on         => $_->{last_on},
  }} @users;

  return to_json \@result;
};

swagger_path {
  tags => ['User'],
  path => (setting('api_base') || '').'/user',
  description => 'Provision a service account and issue an API token. Creates the user if not present (null password, token-auth only). Idempotent.',
  parameters => [
    body => {
      in => 'body',
      schema => {
        type => 'object',
        required => ['username'],
        properties => {
          username => {
            type => 'string',
            description => 'Username of the service account',
          },
          permanent => {
            type => 'boolean',
            default => 0,
            description => 'Issue a non-expiring token (requires allow_permanent_tokens in config)',
          },
          allowed_ips => {
            type => 'array',
            items => { type => 'string' },
            description => 'CIDR prefixes allowed to use this token (omit for no restriction)',
          },
          revoke => {
            type => 'boolean',
            default => 0,
            description => 'Revoke the token instead of issuing one',
          },
        },
      },
    },
  ],
  responses => { default => { examples => {
    'application/json' => { username => 'grafana-svc', api_key => 'cc9d5c02d8898e5728b7d7a0339c0785', permanent => 1 },
  } } },
}, post '/api/v1/user' => require_role api_admin => sub {
  header('Content-Type' => 'application/json');

  my $body = try { from_json(request->body) } catch { {} };
  my $username = $body->{username}
    or return send_error(to_json({ error => 'Missing username' }), 400);

  my $user = schema('netdisco')->resultset('User')
    ->find_or_create({ username => $username });

  if ($body->{revoke}) {
    $user->update({ token => undef, token_from => undef, token_no_expire => \"false",
                    token_allowed_ips => undef });
    return to_json { username => $username, revoked => \1 };
  }

  my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');

  my $want_permanent = $body->{permanent} && setting('allow_permanent_tokens');
  my $allowed_ips    = (ref $body->{allowed_ips} eq ref []) ? $body->{allowed_ips} : undef;

  $user->update({
    token_from      => time,
    token_no_expire => ($want_permanent ? \"true" : \"false"),
    (defined $allowed_ips ? (token_allowed_ips => $allowed_ips) : ()),
    ($provider->validate_api_token($user->token)
      ? () : (token => \'md5(random()::text)')),
  })->discard_changes();

  return to_json {
    username  => $username,
    api_key   => $user->token,
    permanent => ($user->token_no_expire ? \1 : \0),
    ($user->token_allowed_ips
      ? (allowed_ips => $user->token_allowed_ips) : ()),
  };
};

true;
