package App::Netdisco::Web::Auth::Provider::DBIC;

use strict;
use warnings;

use base 'Dancer::Plugin::Auth::Extensible::Provider::Base';

# with thanks to yanick's patch at
# https://github.com/bigpresh/Dancer-Plugin-Auth-Extensible/pull/24

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Passphrase;
use Digest::MD5;
use Net::LDAP;
use Authen::Radius;
use Authen::TacacsPlus;
use Path::Class;
use File::ShareDir 'dist_dir';
use Try::Tiny;

sub authenticate_user {
    my ($self, $username, $password) = @_;
    return unless defined $username;

    my $user = $self->get_user_details($username) or return;
    return unless $user->in_storage;
    return $self->match_password($password, $user);
}

sub get_user_details {
    my ($self, $username) = @_;

    my $settings = $self->realm_settings;
    my $database = schema($settings->{schema_name})
        or die "No database connection";

    my $users_table     = $settings->{users_resultset}       || 'User';
    my $username_column = $settings->{users_username_column} || 'username';

    my $user = try {
      $database->resultset($users_table)->find({
          # FIXME: ILIKE to get case insensitive match on username, no wildcards
          $username_column => { -ilike => quotemeta($username) },
      });
    };

    # each of these settings permits no user in the database
    # so create a pseudo user entry instead
    if (not $user and
        (setting('no_auth') or
          (not setting('validate_remote_user')
           and (setting('trust_remote_user') or setting('trust_x_remote_user')) ))) {

        $user = $database->resultset($users_table)
          ->new_result({username => $username});
    }

    return $user;
}

sub validate_api_token {
    my ($self, $token) = @_;
    return unless defined $token;

    my $settings = $self->realm_settings;
    my $database = schema($settings->{schema_name})
        or die "No database connection";

    my $users_table  = $settings->{users_resultset}    || 'User';
    my $token_column = $settings->{users_token_column} || 'token';

    $token =~ s/^Apikey //i; # should be there but swagger-ui doesn't add it
    my $user = try {
      $database->resultset($users_table)->find({ $token_column => $token });
    };

    return $user
      if $user and $user->in_storage and $user->token_from
        and $user->token_from > (time - setting('api_token_lifetime'));
    return undef;
}

sub get_user_roles {
    my ($self, $username) = @_;
    return unless defined $username;

    my $settings = $self->realm_settings;
    my $database = schema($settings->{schema_name})
        or die "No database connection";

    # Get details of the user first; both to check they exist, and so we have
    # their ID to use.
    my $user = $self->get_user_details($username)
        or return;

    my $roles       = $settings->{roles_relationship} || 'roles';
    my $role_column = $settings->{role_column}        || 'role';

    # this method returns a list of current user roles
    # but for API with trust_remote_user, trust_x_remote_user, and no_auth
    # we need to fake that there is a valid API key

    my $api_requires_key =
      (setting('trust_remote_user') or setting('trust_x_remote_user') or setting('no_auth'))
        eq '1' ? 'false' : 'true';

    return [ try {
      $user->$roles->search({}, { bind => [
          $api_requires_key, setting('api_token_lifetime'),
          $api_requires_key, setting('api_token_lifetime'),
        ] })->get_column( $role_column )->all;
    } ];
}

sub match_password {
    my($self, $password, $user) = @_;
    return unless $user;

    my $settings = $self->realm_settings;
    my $username_column = $settings->{users_username_column} || 'username';

    my $pwmatch_result = 0;
    my $username = $user->$username_column;

    if ($user->ldap) {
      $pwmatch_result = $self->match_with_ldap($password, $username);
    }
    elsif ($user->radius) {
      $pwmatch_result = $self->match_with_radius($password, $username);
    }
    elsif ($user->tacacs) {
      $pwmatch_result = $self->match_with_tacacs($password, $username);
    }
    else {
      $pwmatch_result = $self->match_with_local_pass($password, $user);
    }

    return $pwmatch_result;
}

sub match_with_local_pass {
    my($self, $password, $user) = @_;

    my $settings = $self->realm_settings;
    my $password_column = $settings->{users_password_column} || 'password';

    return unless $password and $user->$password_column;

    if ($user->$password_column !~ m/^{[A-Z]+}/) {
        my $sum = Digest::MD5::md5_hex($password);

        if ($sum eq $user->$password_column) {
            if (setting('safe_password_store')) {
                # upgrade password if successful, and permitted
                $user->update({password => passphrase($password)->generate});
            }
            return 1;
        }
        else {
            return 0;
        }
    }
    else {
        return passphrase($password)->matches($user->$password_column);
    }
}

sub match_with_ldap {
    my($self, $pass, $user) = @_;

    return unless setting('ldap') and ref {} eq ref setting('ldap');
    my $conf = setting('ldap');

    my $ldapuser = $conf->{user_string};
    $ldapuser =~ s/\%USER\%?/$user/egi;

    # If we can bind as anonymous or proxy user,
    # search for user's distinguished name
    if ($conf->{proxy_user}) {
        my $user   = $conf->{proxy_user};
        my $pass   = $conf->{proxy_pass};
        my $attrs  = ['distinguishedName'];
        my $result = _ldap_search($ldapuser, $attrs, $user, $pass);
        $ldapuser  = $result->[0] if ($result->[0]);
    }
    # otherwise, if we can't search and aren't using AD and then construct DN
    # by appending base
    elsif ($ldapuser =~ m/=/) {
        $ldapuser = "$ldapuser,$conf->{base}";
    }

    foreach my $server (@{$conf->{servers}}) {
        my $opts = $conf->{opts} || {};
        my $ldap = Net::LDAP->new($server, %$opts) or next;
        my $msg  = undef;

        if ($conf->{tls_opts} ) {
            $msg = $ldap->start_tls(%{$conf->{tls_opts}});
        }

        $msg = $ldap->bind($ldapuser, password => $pass);
        $ldap->unbind(); # take down session

        return 1 unless $msg->code();
    }

    return undef;
}

sub _ldap_search {
    my ($filter, $attrs, $user, $pass) = @_;
    my $conf = setting('ldap');

    return undef unless defined($filter);
    return undef if (defined $attrs and ref [] ne ref $attrs);

    foreach my $server (@{$conf->{servers}}) {
        my $opts = $conf->{opts} || {};
        my $ldap = Net::LDAP->new($server, %$opts) or next;
        my $msg  = undef;

        if ($conf->{tls_opts}) {
            $msg = $ldap->start_tls(%{$conf->{tls_opts}});
        }

        if ( $user and $user ne 'anonymous' ) {
            $msg = $ldap->bind($user, password => $pass);
        }
        else {
            $msg = $ldap->bind();
        }

        $msg = $ldap->search(
          base   => $conf->{base},
          filter => "($filter)",
          attrs  => $attrs,
        );

        $ldap->unbind(); # take down session

        my $entries = [$msg->entries];
        return $entries unless $msg->code();
    }

    return undef;
}

sub match_with_radius {
  my($self, $pass, $user) = @_;
  return unless setting('radius') and ref {} eq ref setting('radius');

  my $conf = setting('radius');
  my $servers = (ref [] eq ref $conf->{'server'}
    ? $conf->{'server'} : [$conf->{'server'}]);
  my $radius = Authen::Radius->new(
    NodeList => $servers,
    Secret   => $conf->{'secret'},
    TimeOut  => $conf->{'timeout'} || 15,
  );
  my $dict_dir = Path::Class::Dir->new( dist_dir('App-Netdisco') )
    ->subdir('contrib')->subdir('raddb')->file('dictionary')->stringify;
  Authen::Radius->load_dictionary($dict_dir);

  $radius->add_attributes(
     { Name => 'User-Name',         Value => $user },
     { Name => 'User-Password',     Value => $pass }
  );

  if ($conf->{'vsa'}) {
    foreach my $vsa (@{$conf->{'vsa'}}) {
      $radius->add_attributes(
        {
          Name   => $vsa->{'name'},
          Value  => $vsa->{'value'},
          Type   => $vsa->{'type'},
          Vendor => $vsa->{'vendor'},
          Tag    => $vsa->{'tag'}
        },
      );
    }
  }


  $radius->send_packet(ACCESS_REQUEST);

  my $type = $radius->recv_packet();
  my $radius_return = ($type eq ACCESS_ACCEPT) ? 1 : 0;

  return $radius_return;
}

sub match_with_tacacs {
  my($self, $pass, $user) = @_;
  return unless setting('tacacs') and ref [] eq ref setting('tacacs');

  my $conf = setting('tacacs');
  my $tacacs = new Authen::TacacsPlus(@$conf);
  if (not $tacacs) {
      debug sprintf('auth error: Authen::TacacsPlus: %s', Authen::TacacsPlus::errmsg());
      return undef;
  }

  my $tacacs_return = $tacacs->authen($user,$pass);
  if (not $tacacs_return) {
      debug sprintf('error: Authen::TacacsPlus: %s', Authen::TacacsPlus::errmsg());
  }
  $tacacs->close();

  return $tacacs_return;
}

1;
