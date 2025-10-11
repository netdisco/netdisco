package App::Netdisco::Web::Plugin::AdminTask::RolePermissionsEditor;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;

use App::Netdisco::Web::Plugin;

register_admin_task({
    tag => "rolepermissionseditor",
    label => "Role Permissions Editor",
    hidden => true,
});

get '/ajax/content/admin/rolepermissionseditor' => require_role admin => sub {
    my $role = param('role_name');
    send_error('Bad Request', 400) unless $role;

    my $rows = schema(vars->{'tenant'})->resultset('PortCtlRole')
      ->search({role_name => $role}, { prefetch => [qw/device_acl port_acl/],
                                       order_by => 'me.id' })
      or send_error('Bad Request', 400);

    template 'ajax/admintask/rolepermissionseditor.tt', {
      role_name => $role,
      results => $rows,
    }, { layout => undef };
};

post '/ajax/control/admin/rolepermissionseditor/add' => require_role admin => sub {
    my $role = param("role_name");
    my $device_rule = param("device_rule");
    my $port_rule = param("port_rule");

    unless ($role and $device_rule) {
      send_error('Bad request', 400);
    }

    schema(vars->{'tenant'})->txn_do(sub {
        my $row = schema(vars->{'tenant'})->resultset('PortCtlRole')
            ->create({
              role_name => $role,
              device_acl => {}, port_acl => {},
            });
        $row->device_acl->update({
              rules => [ $device_rule ],
        });
        $row->port_acl->update({
              rules => [ $port_rule ],
        }) if $port_rule;
    });
};

post '/ajax/control/admin/rolepermissionseditor/delete' => require_role admin => sub {
    my $id = param("id");
    send_error('Bad Request', 400) unless $id;
    
    schema(vars->{'tenant'})->txn_do(sub {
        my $row = schema(vars->{'tenant'})->resultset('PortCtlRole')
          ->find($id);
        schema(vars->{'tenant'})->resultset('AccessControlList')
          ->find($row->device_acl_id)->delete;
        schema(vars->{'tenant'})->resultset('AccessControlList')
          ->find($row->port_acl_id)->delete;
        $row->delete;
    });
};

post '/ajax/control/admin/rolepermissionseditor/update' => require_role admin => sub {
    my $acl = param("acl");
    my $new_acl = param("new-acl");
    my $device = param("device");
    my $new_device = param("new-device");
    my $role = param("role");

    unless ($device and $role and $acl) {
      send_error('Bad request', 400);
    }
    my $rs = schema(vars->{'tenant'})->resultset('PortCtlRoleDevicePort');
    my $portctl_acl = $rs->find({ device_ip => $device, role_name => $role, acl => $acl});

    return unless $portctl_acl;

    if ($portctl_acl) {
        schema(vars->{'tenant'})->txn_do(sub {
            $portctl_acl->update({
                (($device ne $new_device)
                  ? (device_ip => $new_device)
                : ()),
                (($acl ne $new_acl)
                  ?(acl => $new_acl)
                 : ())
            });
        });
    }
};

true;

