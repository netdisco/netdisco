package App::Netdisco::Worker::Plugin::Macsuck::InterfacesStatus;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';
use Dancer::Plugin::DBIC 'schema';

register_worker({ phase => 'main', driver => 'snmp',
  title => 'gather interfaces status from snmp'}, sub {

  my ($job, $workerconf) = @_;
  my $device = $job->device;

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
    or return Status->info("skip: could not SNMP connect to $device");

  my $interfaces = $snmp->interfaces || {};
  my $reverse_interfaces = { reverse %{ $interfaces } }; # might squash but prob not

  my $i_up       = $snmp->i_up;
  my $i_up_admin = $snmp->i_up_admin;

  # make sure ports reflect their latest state as reported by device
  foreach my $port (keys %{ vars->{'device_ports'} }) {
    my $iid = $reverse_interfaces->{$port} or next;

    debug sprintf ' [%s] macsuck - updating port %s status : %s/%s',
      $device->ip, $port, ($i_up_admin->{$iid} || '-'), ($i_up->{$iid} || '-');

    vars->{'device_ports'}->{$port}->set_column(up => $i_up->{$iid});
    vars->{'device_ports'}->{$port}->set_column(up_admin => $i_up_admin->{$iid});
  }

  return Status->info('interfaces status from snmp complete');
});

register_worker({ phase => 'store',
  title => 'update interfaces status in database'}, sub {

  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # make sure ports are UP in netdisco (unless it's a lag master,
  # because we can still see nodes without a functioning aggregate)

  my %port_seen = ();
  foreach my $vlan (reverse sort keys %{ vars->{'fwtable'} }) {
    foreach my $port (keys %{ vars->{'fwtable'}->{$vlan} }) {
        next if $port_seen{$port};
        ++$port_seen{$port};

        next unless scalar keys %{ vars->{'fwtable'}->{$vlan}->{$port} };
        next unless exists vars->{'device_ports'}->{$port};
        next if vars->{'device_ports'}->{$port}->is_master;

        debug sprintf ' [%s] macsuck - updating port %s status up/up due to node presence',
          $device->ip, $port;

        vars->{'device_ports'}->{$port}->set_column(up => 'up');
        vars->{'device_ports'}->{$port}->set_column(up_admin => 'up');
    }
  }

  my $updated = 0;
  foreach my $port (values %{ vars->{'device_ports'} }) {
    next unless $port->is_changed();
    $port->update();
    ++$updated;
  }

  return Status->info(sprintf '%s interfaces status updated in database', $updated);
});

true;
