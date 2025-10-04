package App::Netdisco::Web::Plugin::AdminTask::DevicePortctl;

use Dancer ':syntax';
use Dancer;
use Dancer::Plugin::DBIC;


use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Web::Plugin;
use Dancer::Plugin::Ajax;


register_admin_task({
    tag => "deviceportctl",
    label => "Device Port Control",
    hidden => true,
});

get '/ajax/content/admin/deviceportctl' => require_role admin => sub {
    my $role = param('role');
    my @device_netdisco_acls = schema(vars->{'tenant'})
        ->resultset('PortctlRoleDevicePort')->get_acls($role);
    my @results;
    foreach (@device_netdisco_acls)
    {
        my $temp = { device_ip => $_->device_ip, acl => $_->acl, role_name => $_->role_name, device_name => schema(vars->{'tenant'})->resultset('Device')->search_for_device($_->device_ip)->name };
        push(@results, $temp);
    }

    content_type('text/html');
    template 'ajax/admintask/deviceportctl.tt', {
      results => \@results,
      role => $role,
    }, { layout => undef };
    
};

post '/ajax/control/admin/deviceportctl/add' => require_role admin => sub {
    my $acl = param("acl");
    my $device = param("device");
    my $role = param("role");

    unless ($device and $role and $acl) {
      send_error('Bad request', 400);
    }

    my $device_ip = schema(vars->{'tenant'})->resultset('Device')->search_for_device($device)->ip;

    my $rs = schema(vars->{'tenant'})->resultset('PortctlRoleDevicePort');
    my $port_control = $rs->search({ device_ip => $device_ip, role_name => $role, acl => $acl})->single;

    return if $port_control;
    schema(vars->{'tenant'})->txn_do(sub {
        $rs->create({
            device_ip => $device_ip,
            role_name => $role,
            acl => $acl,
        });
    });
    
    return 200;
};

post '/ajax/control/admin/deviceportctl/del' => require_role admin => sub {
    my $acl = param("acl");
    my $device = param("device");
    my $role = param("role");
    
    unless ($device and $role and $acl) {
      send_error('Bad request', 400);
    }

    my $device_ip = schema(vars->{'tenant'})->resultset('Device')->search_for_device($device)->ip;

    schema(vars->{'tenant'})->txn_do(sub {
        schema(vars->{'tenant'})->resultset('PortctlRoleDevicePort')
          ->find({ device_ip => $device_ip, role_name => $role, acl => $acl })->delete
    });
};

post '/ajax/control/admin/deviceportctl/update' => require_role admin => sub {
    my $acl = param("acl");
    my $new_acl = param("new-acl");
    my $device = param("device");
    my $new_device = param("new-device");
    my $role = param("role");

    unless ($device and $role and $acl) {
      send_error('Bad request', 400);
    }


    my $device_ip = schema(vars->{'tenant'})->resultset('Device')->search_for_device($device)->ip;

    my $rs = schema(vars->{'tenant'})->resultset('PortctlRoleDevicePort');
    my $portctl_acl = $rs->find({ device_ip => $device_ip, role_name => $role, acl => $acl});

    return unless $portctl_acl;

    if ($portctl_acl) {
        schema(vars->{'tenant'})->txn_do(sub {
            $portctl_acl->update({
                (($device ne $new_device)
                  ? (device_ip => $device_ip)
                : ()),
                (($acl ne $new_acl)
                  ?(acl => $acl)
                 : ())
            });
        });
    }
};

true;

