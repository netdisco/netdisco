package App::Netdisco::Web::Plugin::AdminTask::RolePerm;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;
use App::Netdisco::Web::Plugin;

register_javascript('roleperm');

register_admin_task({
    tag => "roleperm",
    label => "Role Permissions"
});


ajax '/ajax/content/admin/roleperm' => require_role admin => sub {

    # to chose which devices to add/remove from the role permissions
    my @devices = schema(vars->{'tenant'})->resultset('Device')->search({
      serial => { '-in' => schema(vars->{'tenant'})->resultset('Device')->search({
          '-and' => [serial => { '!=', undef }, serial => { '!=', '' }],
        }, {
          group_by => ['serial'],

          columns => 'serial',
        })->as_query
      },
    }, { columns => [qw/ip dns name/] })
      ->with_times->hri->all;
    
    my @roles = schema(vars->{'tenant'})->resultset('PortCtlRole')->get_roles;

    my %set;
    foreach my $role (@roles) {
        $set{$role} = [];
    }

    my $rs = schema(vars->{'tenant'})->resultset('PortCtlRoleDevice');
    my $port_control = $rs->search({}, { order_by => 'role_name' });

    while (my $row = $port_control->next) {
        my $role = $row->role_name;
        my $device_ip = $row->device_ip;
        my $device = schema(vars->{'tenant'})->resultset('Device')->find({ ip => $device_ip });
        next unless $device;

        my $device_name = $device ? $device->name : $device_ip;
        # Push the device info into the role's array
        push @{$set{$role}}, {
            device_ip => $device_ip,
            device_name => $device_name,
        };
    }
    template 'ajax/admintask/roleperm.tt', {
      results => \%set,
      devices => \@devices,
    }, { layout => undef };

};



ajax '/ajax/control/admin/roleperm/add' => require_role admin => sub {
    my $role = param('role');
    return { success => 0, message => "Role name cannot be empty" } unless $role;
    # check if the role already exists
    my $existing_role = schema(vars->{'tenant'})->resultset('PortCtlRole')->find({ role_name => $role });
    if ($existing_role) {
        debug '/rolepemp/add: Role already exists';
        return { success => 0, message => "Role '$role' already exists" };
    }
    # create the new role
    schema(vars->{'tenant'})->txn_do(sub {
        my $new_role = schema(vars->{'tenant'})->resultset('PortCtlRole')->create({ role_name => $role });
    });
    debug '/roleperm/add: Created new role ' . $role;
    return to_json({ success => 1, message => "Role '$role' created successfully" });
};


ajax '/ajax/control/admin/roleperm/update' => require_role admin => sub {
    my $role = param('role');
    my $old_role_name = param('old-role');
    return { success => 0, message => "Role name cannot be empty" } unless $role;
    # check if the role already exists
    if ($role ne $old_role_name) {
        my $existing_role = schema(vars->{'tenant'})->resultset('PortCtlRole')->find({ role_name => $role });
        if ($existing_role) {
            debug '/roleperm/update: Role already exists';
            return { success => 0, message => "Role '$role' already exists" };
        }
        # update the role name
        my $role_rs = schema(vars->{'tenant'})->resultset('PortCtlRole')->find({ role_name => $old_role_name });
        if ($role_rs) {

            schema(vars->{'tenant'})->txn_do(sub {
                # update role of users that have this role
                my $user_rs = schema(vars->{'tenant'})->resultset('User')->search({ portctl_role => $old_role_name });
                while (my $user = $user_rs->next) {
                    $user->update({ portctl_role => $role });
                }
                # update the role name
                $role_rs->update({ role_name => $role });
                # update all permissions associated with the old role name
                my $device_perms = schema(vars->{'tenant'})->resultset('PortCtlRoleDevice')->search({ role_name => $old_role_name });
                while (my $perm = $device_perms->next) {
                    $perm->update({ role_name => $role });
                }
                my $port_perms = schema(vars->{'tenant'})->resultset('PortCtlRoleDevicePort')->search({ role_name => $old_role_name });
                while (my $perm = $port_perms->next) {
                    $perm->update({ role_name => $role });
                }
            });
            debug '/roleperm/update: Updated role ' . $old_role_name . ' to ' . $role;
            return to_json({ success => 1, message => "Updated $old_role_name to $role" });

        } else {
            debug '/roleperm/update: Role does not exist';
            return to_json({ success => 0, message => "Role '$old_role_name' does not exist" });
        }
    }

    # bad request if we reach here
    send_error('Bad Request', 400)
 

    # create the new role
};

ajax '/ajax/control/admin/roleperm/del' => require_role admin => sub {
    my $role = param('role');
    return { success => 0, message => "Role name cannot be empty" } unless $role;
    # check if the role exists
    my $existing_role = schema(vars->{'tenant'})->resultset('PortCtlRole')->find({ role_name => $role });
    if ($existing_role) {
        schema(vars->{'tenant'})->txn_do(sub {
            $existing_role->delete;
            foreach my $permission (schema(vars->{'tenant'})->resultset('PortCtlRoleDevice')->search({ role_name => $role })->all) {
                $permission->delete;
            }
            foreach my $permission (schema(vars->{'tenant'})->resultset('PortCtlRoleDevicePort')->search({ role_name => $role })->all) {
                $permission->delete;
            }
        });
        debug '/roleperm/del: Deleted role ' . $role;
        return to_json({ success => 1, message => "Role '$role' deleted successfully" });
    } else {
        debug '/roleperm/del: Role does not exist';
        return to_json({ success => 0, message => "Role '$role' does not exist" });
    }
    send_error('Bad Request', 400)
};

ajax '/ajax/control/admin/roleperm/devices' => require_role admin => sub {

    my $device_ips = param('device-list'); # this is a string containing device names delimited by commas
    my $role = param('role');
    my @current_perm = schema(vars->{'tenant'})->resultset('PortCtlRoleDevice')->search({ role_name => $role })->all;


    my @device_ips = split /,/ , $device_ips;
    @device_ips = map { s/^\s+|\s+$//g; $_ } @device_ips;

    my %current_ips = map { $_->device_ip => 1 } @current_perm;
    my %new_ips = map { $_ => 1 } @device_ips;


    # remove entries if some devices are not in the new list anymore
    foreach my $current_ip (keys %current_ips) {
        unless ($new_ips{lc $current_ip}) {
            my $permission = schema(vars->{'tenant'})->resultset('PortCtlRoleDevice')->find({
                device_ip => $current_ip,
                role_name => $role,
            });
            if ($permission) {
                $permission->delete;
            }
        }
    }
    # add entries for new devices
    foreach my $new_ip (keys %new_ips) {
        unless ($current_ips{lc $new_ip}) {
            my $device = schema(vars->{'tenant'})->resultset('Device')->find({ ip => $new_ip });
            if ($device) {
                schema(vars->{'tenant'})->resultset('PortCtlRoleDevice')->create({
                    device_ip => $new_ip,
                    role_name => $role,
                });
            }
        }
    }
    # count the number of devices in the role
    debug '/roleperm/devices: Updated permissions for role ' . $role . ' with  ' . scalar(keys %new_ips) . ' devices';
    return to_json({ success => 1, message => "Permissions updated successfully" });

};
####################
true;

