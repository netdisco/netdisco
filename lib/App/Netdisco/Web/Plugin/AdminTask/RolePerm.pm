package App::Netdisco::Web::Plugin::AdminTask::RolePerm;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;
use App::Netdisco::Web::Plugin;


register_admin_task({
    tag => "roleperm",
    label => "Role Permissions"
});

register_javascript('roleperm');

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
    
    my @roles = schema(vars->{'tenant'})->resultset('PortctlRole')->get_roles;

    my %set;
    foreach my $role (@roles) {
        $set{$role} = [];
    }

    my $rs = schema(vars->{'tenant'})->resultset('PortctlRoleDevice');
    my $port_control = $rs->search({}, { order_by => 'role' });

    while (my $row = $port_control->next) {
        my $role = $row->role;
        my $device_ip = $row->device_ip;
        my $device = schema(vars->{'tenant'})->resultset('Device')->find({ ip => $device_ip });
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


post '/ajax/content/admin/roleperm' => require_role admin => sub {
  
    my $device_ips = param('device-list'); # this is a string containing device names delimited by commas
    my $role = param('role');
    my @current_perm = schema(vars->{'tenant'})->resultset('PortctlRoleDevice')->search({ role => $role })->all;


    my @device_ips = split /,/ , $device_ips;
    @device_ips = map { s/^\s+|\s+$//g; $_ } @device_ips;

    my %current_ips = map { $_->device_ip => 1 } @current_perm;
    my %new_ips = map { $_ => 1 } @device_ips;


    # remove entries if some devices are not in the new list anymore
    foreach my $current_ip (keys %current_ips) {
        unless ($new_ips{lc $current_ip}) {
            my $permission = schema(vars->{'tenant'})->resultset('PortctlRoleDevice')->find({
                device_ip => $current_ip,
                role => $role,
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
                schema(vars->{'tenant'})->resultset('PortctlRoleDevice')->create({
                    device_ip => $new_ip,
                    role => $role,
                });
            }
        }
    }

    return { success => 1, message => "Permission updated successfully" };

};
####################
true;

