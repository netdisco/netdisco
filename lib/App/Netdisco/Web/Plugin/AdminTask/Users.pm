package App::Netdisco::Web::Plugin::AdminTask::Users;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Passphrase;

use App::Netdisco::Web::Plugin;
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

ajax '/ajax/control/admin/users/add' => require_role setting('defanged_admin') => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      my $user = schema('netdisco')->resultset('User')
        ->create({
          username => param('username'),
          password => _make_password(param('password')),
          fullname => param('fullname'),
          ldap => (param('ldap') ? \'true' : \'false'),
          port_control => (param('port_control') ? \'true' : \'false'),
          admin => (param('admin') ? \'true' : \'false'),
          note => param('note'),
        });
    });
};

ajax '/ajax/control/admin/users/del' => require_role setting('defanged_admin') => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('User')
        ->find({username => param('username')})->delete;
    });
};

ajax '/ajax/control/admin/users/update' => require_role setting('defanged_admin') => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      my $user = schema('netdisco')->resultset('User')
        ->find({username => param('username')});
      return unless $user;

      $user->update({
        ((param('password') ne '********')
          ? (password => _make_password(param('password')))
          : ()),
        fullname => param('fullname'),
        ldap => (param('ldap') ? \'true' : \'false'),
        port_control => (param('port_control') ? \'true' : \'false'),
        admin => (param('admin') ? \'true' : \'false'),
        note => param('note'),
      });
    });
};

get '/ajax/content/admin/users' => require_role admin => sub {
    my @results = schema('netdisco')->resultset('User')
      ->search(undef, {
        '+columns' => {
          created   => \"to_char(creation, 'YYYY-MM-DD HH24:MI')",
          last_seen => \"to_char(last_on,  'YYYY-MM-DD HH24:MI')",
        },
        order_by => [qw/fullname username/]
      })->hri->all;

    return unless scalar @results;

    if ( request->is_ajax ) {
        template 'ajax/admintask/users.tt',
            { results => \@results, },
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
