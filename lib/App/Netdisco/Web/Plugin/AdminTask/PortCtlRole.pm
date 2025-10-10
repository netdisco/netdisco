package App::Netdisco::Web::Plugin::AdminTask::PortCtlRole;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;

use App::Netdisco::Web::Plugin;

register_admin_task({
    tag => "portctlrole",
    label => "Port Control Roles"
});

ajax '/ajax/content/admin/portctlrole' => require_role admin => sub {
    my @roles = schema(vars->{'tenant'})->resultset('PortCtlRole')
                                        ->role_names;

    template 'ajax/admintask/portctlrole.tt', {
      results => \@roles,
    }, { layout => undef };
};

ajax '/ajax/control/admin/portctlrole/add' => require_role admin => sub {
    my $role = param('role');
    send_error('Bad Request', 400) unless $role;

    # create the new role
    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('PortCtlRole')
                              ->find_or_create({
                                name => $role,
                                device_acl => {},
                                port_acl => {},
                              });
    });
};

ajax '/ajax/control/admin/portctlrole/delete' => require_role admin => sub {
    my $role = param('role');
    send_error('Bad Request', 400) unless $role;

    schema(vars->{'tenant'})->txn_do(sub {
      my $role = schema(vars->{'tenant'})->resultset('PortCtlRole')
                                         ->find({ name => $role })
        or return;
      $role->device_acl->delete;
      $role->port_acl->delete;
      $role->delete;
    });
};

ajax '/ajax/control/admin/portctlrole/update' => require_role admin => sub {
    my $role = param('role');
    my $old_role = param('old-role');
    send_error('Bad Request', 400) unless $role and $old_role;

    schema(vars->{'tenant'})->txn_do(sub {
      my $role = schema(vars->{'tenant'})->resultset('PortCtlRole')
                                         ->find({ name => $old_role })
                                         ->update({ name => $role });
    });
};

true;

