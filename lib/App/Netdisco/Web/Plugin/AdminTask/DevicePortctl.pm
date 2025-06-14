package App::Netdisco::Web::Plugin::AdminTask::DevicePortctl;

use Dancer ':syntax';
use Dancer;
use App::Netdisco::Util::Permission 'acl_matches';
use Dancer::Plugin::DBIC;

use App::Netdisco::Util::Port 'port_acl_by_role_check';

use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Web::Plugin;
use Dancer::Plugin::Ajax;


register_admin_task({
    tag => "deviceportctl",
    hidden => true,
});



ajax '/ajax/content/admin/deviceportctl' => require_role admin => sub {
    # Ok, this is really clunky tbh
    # Making a pseudo device ports view based solely on port names is really not optimal but it works, will change it later :)

    my $reverse_mapping = {
        'Fa'  => 'FastEthernet',   'Gi'  => 'GigabitEthernet',
        'Tw'  => 'TwoGigabitEth',  'Te'  => 'TenGigabitEthernet',
        'Twe' => 'TwentyFiveGigE', 'Fo'  => 'FortyGigE',
        'Fi'  => 'FiftyGigE',      'Hu'  => 'HundredGigE'
    };
    my $if_mapping = {
        "ethernet"        => "",   "fastethernet"     => "Fa",
        "gigabitethernet" => "Gi", "twogigabiteth"    => "Tw",
        "tengigabitethernet" => "Te", "twentyfivegige" => "Twe",
        "fortygige"       => "Fo", "fiftygige"        => "Fi",
        "hundredgige"     => "Hu"
    };

    my $role = param("q");
    my @devices = schema(vars->{'tenant'})
        ->resultset('PortctlRoleDevice')->get_role_permissions($role);

    foreach my $dev (@devices) {
      my $device = schema(vars->{'tenant'})->resultset('Device')->search_for_device($dev->device_ip);
      next unless $device;
      $dev->{name} = $device->name;

      my $portset = $device->ports->with_properties;

      my @results = $portset->search({}, { order_by => { -asc => 'ifindex'}})->all;

      my $port_map = {};
      my %to_hide  = ();

      map { push @{ $port_map->{$_->port} }, $_ }
            grep { $_->port }
            @results;

      map { push @{ $port_map->{$_->port} }, $_ }
          grep { $_->port }
          $device->device_ips()->all;

      foreach my $map (@{ setting('hide_deviceports')}) {
          next unless ref {} eq ref $map;

          foreach my $key (sort keys %$map) {
              # lhs matches device, rhs matches port
              next unless $key and $map->{$key};
              next unless acl_matches($device, $key);

              foreach my $port (sort keys %$port_map) {
                  next unless acl_matches($port_map->{$port}, $map->{$key});
                  ++$to_hide{$port};
              }
          }
      }

      @results = grep { ! exists $to_hide{$_->port} } @results;

      my %final_ports;
      foreach my $port (@ports) {
          my $vendor = $device->vendor;
          my $port_name = $port->port;
          my $stack_number = 0;

          # Stack number extraction
          if ($vendor eq 'cisco') {
              ($stack_number) = ($port_name =~ /^\D+(\d+)/);
              $stack_number = (split /\//, $stack_number)[0];
          } elsif ($vendor eq 'avaya') {
              ($stack_number) = split(/\./, $port_name);
          }

          # Shorten port name for Cisco
          if ($vendor eq 'cisco') {
              foreach my $mapping (keys %$if_mapping) {
                  if (lc($port_name) =~ /^$mapping/) {
                      my $key = $if_mapping->{$mapping};
                      $port_name =~ s/$mapping/$key/i;
                      last;
                  }
              }
          }

          my $can_admin = port_acl_by_role_check($port->port, $device, $role);
          push @{ $final_ports{$stack_number} }, {
              short     => $port_name,
              long      => $port->port,
              can_admin => $can_admin,
          };
      }

      # Sort stack indexes
      my @chassis_indexes = sort keys %final_ports;

      # Split ports into odd/even for each stack/module
      foreach my $i (keys %final_ports) {
          my @odd_ports;
          my @even_ports;
          my $ports = $final_ports{$i};
          my $size = scalar @$ports;
          my $iter = 0;

          while ($iter < $size) {
              my $first  = $ports->[$iter];
              my $second = ($iter + 1 < $size) ? $ports->[$iter + 1] : { long => "empty", short => "", can_admin => 0 };

              if (substr($first->{long}, -1) % 2 == 0) {
                  push @even_ports, $first;
                  if ($iter == 0) {
                      push @odd_ports, { long => "empty", short => "", can_admin => 0 };
                      $iter--;
                  } else {
                      push @odd_ports, $second;
                  }
              } else {
                  push @odd_ports, $first;
                  push @even_ports, $second;
              }
              $iter += 2;
          }
          $final_ports{$i} = { odd => \@odd_ports, even => \@even_ports };
      }

      $dev->{ports} = \@results;
      $dev->{modules} = \%$final_ports;
      $dev->{stack} = \@chassis_indexes;
    }
    

    content_type('text/html');
    template 'ajax/admintask/portpermissions/grouptodevicemapping.tt', {
      results => \@devices,
      role => $role,
    }, { layout => undef };
    
};


post '/ajax/control/admin/deviceportctl' => require_role admin => sub {
    my $req_json = param("data");
    $req_json = from_json($req_json);
    my $device = $req_json->{device};
    my $role = $req_json->{group};

    my $device_ports = $req_json->{ports};
    unless ($device and $role) {
      send_error('Bad request', 400);
    }
    my $device_ip = schema(vars->{'tenant'})->resultset('Device')->find({ name => $device  })->get_column('ip');

    my $rs = schema(vars->{'tenant'})->resultset('RoleDevicePortPermission');
    my $port_control = $rs->search({ device_ip => $device_ip, role => $role });

    foreach my $port (keys %$device_ports) {
        my $port_name = $port;

        my $can_admin = $device_ports->{$port_name};

        my $existing_port = $port_control->find({ port => $port_name });

        if ($existing_port) {
            $existing_port->update({ can_admin => $can_admin });
        } else {
            $rs->create({
                role => $role,
                device_ip => $device_ip,
                port => $port_name,
                can_admin => $can_admin,
            });
        }
    }
};

true;

