package App::Netdisco::Web::Plugin::AdminTask::Users;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;
use Digest::MD5 ();

register_admin_task({
  tag => 'users',
  label => 'User Management',
});

sub _sanity_ok {
    return 0 unless var('user') and var('user')->admin;

    return 0 unless param('username')
      and param('username') =~ m/^[[:print:]]+$/
      and param('username') !~ m/[[:space:]]/;

    return 1;
}

ajax '/ajax/control/admin/users/add' => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      my $user = schema('netdisco')->resultset('User')
        ->create({
          username => param('username'),
          password => Digest::MD5::md5_hex(param('password')),
          fullname => param('fullname'),
          port_control => (param('port_control') ? \'true' : \'false'),
          admin => (param('admin') ? \'true' : \'false'),
        });
    });
};

ajax '/ajax/control/admin/users/del' => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('User')
        ->find({username => param('username')})->delete;
    });
};

ajax '/ajax/control/admin/users/update' => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      my $user = schema('netdisco')->resultset('User')
        ->find({username => param('username')});
      return unless $user;

      $user->update({
        ((param('password') ne '********')
          ? (password => Digest::MD5::md5_hex(param('password')))
          : ()),
        fullname => param('fullname'),
        port_control => (param('port_control') ? \'true' : \'false'),
        admin => (param('admin') ? \'true' : \'false'),
      });
    });
};

ajax '/ajax/content/admin/users' => sub {
    send_error('Forbidden', 403) unless var('user')->admin;

    my $set = schema('netdisco')->resultset('User')
      ->search(undef, { order_by => [qw/fullname username/]});

    content_type('text/html');
    template 'ajax/admintask/users.tt', {
      results => $set,
    }, { layout => undef };
};

true;
