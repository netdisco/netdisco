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
      results => [sort @roles],
    }, { layout => undef };
};

ajax '/ajax/control/admin/portctlrole/add' => require_role admin => sub {
    my $role = param('role_name');
    send_error('Bad Request', 400) unless $role;
    send_error('Bad Request', 400)
      if schema(vars->{'tenant'})->resultset('PortCtlRole')
                                 ->search({role_name => $role})->count();

    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('PortCtlRole')
                              ->create({
                                role_name => $role,
                                device_acl => {}, port_acl => {},
                              });
    });
};

ajax '/ajax/control/admin/portctlrole/delete' => require_role admin => sub {
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
    });
};

ajax '/ajax/control/admin/portctlrole/update' => require_role admin => sub {
    my $role = param('role_name');
    my $old_role = param('old-role_name');
    send_error('Bad Request', 400) unless $role and $old_role;

    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('PortCtlRole')
                              ->search({ role_name => $old_role })
                              ->update({ role_name => $role });
    });
};

true;

