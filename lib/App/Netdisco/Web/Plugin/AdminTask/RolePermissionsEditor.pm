package App::Netdisco::Web::Plugin::AdminTask::RolePermissionsEditor;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;

use App::Netdisco::Web::Plugin;

use MIME::Base64 'decode_base64';

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
    my $id = param("id");
    send_error('Bad Request', 400) unless $id;

    my @device_rules = map {decode_base64($_)} @{ param('device_rule') || [] };
    my @port_rules   = map {decode_base64($_)} @{ param('port_rule') || [] };

    schema(vars->{'tenant'})->txn_do(sub {
        my $row = schema(vars->{'tenant'})->resultset('PortCtlRole')
          ->find($id);
        schema(vars->{'tenant'})->resultset('AccessControlList')
          ->find($row->device_acl_id)->update({rules => \@device_rules });
        schema(vars->{'tenant'})->resultset('AccessControlList')
          ->find($row->port_acl_id)->update({rules => \@port_rules });
    });
};

true;

