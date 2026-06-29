package App::Netdisco::Web::Plugin::AdminTask::ACLManager;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;

use App::Netdisco::Web::Plugin;

register_admin_task({
    tag => "aclmanager",
    label => "Access Control Lists"
});

ajax '/ajax/content/admin/aclmanager' => require_role admin => sub {
    my @names = schema(vars->{'tenant'})->resultset('AccessControlListName')
                                        ->acl_names;

    template 'ajax/admintask/aclmanager.tt', {
      results => [sort @names],
    }, { layout => undef };
};

ajax '/ajax/control/admin/aclmanager/add' => require_role setting('defanged_admin') => sub {
    my $role = param('role_name');
    send_error('Bad Request', 400) unless $role;
    send_error('Bad Request', 400)
      if schema(vars->{'tenant'})->resultset('PortCtlRole')
                                 ->search({role_name => $role})->count();

    schema(vars->{'tenant'})->txn_do(sub {
      my $new = schema(vars->{'tenant'})->resultset('PortCtlRole')
        ->create({
          role_name => $role,
          device_acl => {}, port_acl => {},
        });
      $new->device_acl->update({ rules => ['group:__ANY__'] });
    });

    return '';
};

ajax '/ajax/control/admin/aclmanager/delete' => require_role setting('defanged_admin') => sub {
    my $role = param('role_name');
    send_error('Bad Request', 400) unless $role;

    schema(vars->{'tenant'})->txn_do(sub {
      my $rows = schema(vars->{'tenant'})->resultset('PortCtlRole')
                                         ->search({ role_name => $role })
        or return;

      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->search({id => { -in => [ $rows->device_acls ] }})->delete;
      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->search({id => { -in => [ $rows->port_acls ] }})->delete;

      $rows->delete;

      schema(vars->{'tenant'})->resultset('User')
        ->search({portctl_role => $role})
        ->update({
          ((exists config->{'portctl_by_role_shadow'}->{$role})
            ? () : (portctl_role => undef, port_control => \'false')),
        });
    });

    return '';
};

ajax '/ajax/control/admin/aclmanager/update' => require_role setting('defanged_admin') => sub {
    my $role = param('role_name');
    my $old_role = param('old-role_name');
    send_error('Bad Request', 400) unless $role and $old_role;

    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('PortCtlRole')
        ->search({ role_name => $old_role })
        ->update({ role_name => $role });

      schema(vars->{'tenant'})->resultset('User')
        ->search({ portctl_role => $old_role })
        ->update({ portctl_role => $role });
    });

    return '';
};

true;

