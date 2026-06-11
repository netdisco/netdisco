package App::Netdisco::Web::Plugin::AdminTask::Users;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Passphrase;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Port 'sync_portctl_roles';
use List::MoreUtils 'uniq';
use Digest::MD5 ();

register_admin_task({
  tag => 'users',
  label => 'User Management',
  provides_csv => 1,
});

sub _sanity_ok {
    return 0 unless param('username')
      and param('username') =~ m/^[[:print:] ]+$/;
    return 1;
}

sub _make_password {
  my $pass = (shift || passphrase->generate_random);
  if (setting('safe_password_store')) {
      return passphrase($pass)->generate;
  }
  else {
      return Digest::MD5::md5_hex($pass),
  }
}

sub _provision_token {
  my $user = shift;
  my $provider = Dancer::Plugin::Auth::Extensible::auth_provider('users');
  unless ($provider->validate_api_token($user->token)) {
    $user->update({ token => \'md5(random()::text)', token_from => time });
    $user->discard_changes();
  }
  return $user->token;
}

ajax '/ajax/control/admin/users/add' => require_role setting('defanged_admin') => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    my $token;
    schema(vars->{'tenant'})->txn_do(sub {
      my $user = schema(vars->{'tenant'})->resultset('User')
        ->create({
          username => param('username'),
          fullname => param('fullname'),

          (param('auth_method') eq 'token' ? (
            password => undef,
            ldap => \'false', radius => \'false', tacacs => \'false',
          ) : (
            password => _make_password(param('password')),
            (param('auth_method') ? (
              (ldap => (param('auth_method') eq 'ldap' ? \'true' : \'false')),
              (radius => (param('auth_method') eq 'radius' ? \'true' : \'false')),
              (tacacs => (param('auth_method') eq 'tacacs' ? \'true' : \'false')),
            ) : (
              ldap => \'false',
              radius => \'false',
              tacacs => \'false',
            )),
          )),

          port_control => (param('port_control') ? \'true' : \'false'),
          portctl_role =>
            ((param('port_control') and param('port_control') ne '_global_')
              ? param('port_control') : ''),

          admin => (param('admin') ? \'true' : \'false'),
          note => param('note'),
        });
      $token = _provision_token($user) if param('auth_method') eq 'token';
    });

    return "<span data-nd-api-key=\"$token\"></span>" if $token;
};

ajax '/ajax/control/admin/users/del' => require_role setting('defanged_admin') => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('User')
        ->find({username => param('username')})->delete;
    });
};

ajax '/ajax/control/admin/users/update' => require_role setting('defanged_admin') => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    my $token;
    schema(vars->{'tenant'})->txn_do(sub {
      my $user = schema(vars->{'tenant'})->resultset('User')
        ->find({username => param('username')});
      return unless $user;

      $user->update({
        fullname => param('fullname'),

        (param('auth_method') eq 'token' ? (
          password => undef,
          ldap => \'false', radius => \'false', tacacs => \'false',
        ) : (
          ((param('password') and param('password') ne '********')
            ? (password => _make_password(param('password')))
            : ()),
          (param('auth_method') ? (
            (ldap => (param('auth_method') eq 'ldap' ? \'true' : \'false')),
            (radius => (param('auth_method') eq 'radius' ? \'true' : \'false')),
            (tacacs => (param('auth_method') eq 'tacacs' ? \'true' : \'false')),
          ) : (
            ldap => \'false',
            radius => \'false',
            tacacs => \'false',
          )),
        )),

        port_control => (param('port_control') ? \'true' : \'false'),
        portctl_role =>
          ((param('port_control') and param('port_control') ne '_global_')
            ? param('port_control') : ''),

        admin => (param('admin') ? \'true' : \'false'),
        note => param('note'),
      });
      $token = _provision_token($user) if param('auth_method') eq 'token';
    });

    return "<span data-nd-api-key=\"$token\"></span>" if $token;
};

get '/ajax/content/admin/users' => require_role admin => sub {
    my @results = schema(vars->{'tenant'})->resultset('User')
      ->search(undef, {
        '+columns' => {
          created   => \"to_char(creation, 'YYYY-MM-DD HH24:MI')",
          last_seen => \"to_char(last_on,  'YYYY-MM-DD HH24:MI')",
        },
        order_by => [qw/fullname username/]
      })->hri->all;

    return unless scalar @results;

    sync_portctl_roles();
    my @port_control_roles = keys %{ setting('portctl_by_role') || {} };
    push @port_control_roles,
      schema(vars->{'tenant'})->resultset('PortCtlRole')->role_names;

    if ( request->is_ajax ) {
        template 'ajax/admintask/users.tt',
            { results => \@results, port_control_roles => [ uniq sort {$a cmp $b} @port_control_roles ] },
            { layout  => undef };
    }
    else {
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/admintask/users_csv.tt',
            { results => \@results, },
            { layout  => undef };
    }
};

true;
