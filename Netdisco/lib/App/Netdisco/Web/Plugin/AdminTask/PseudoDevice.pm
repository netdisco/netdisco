package App::Netdisco::Web::Plugin::AdminTask::PseudoDevice;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';

register_admin_task({
  tag => 'pseudodevice',
  label => 'Pseudo Devices',
});

sub _sanity_ok {
    return 0 unless param('dns')
      and param('dns') =~ m/^[[:print:]]+$/
      and param('dns') !~ m/[[:space:]]/;

    my $ip = NetAddr::IP::Lite->new(param('ip'));
    return 0 unless ($ip and$ip->addr ne '0.0.0.0');

    return 0 unless param('ports')
      and param('ports') =~ m/^[[:digit:]]+$/;

    return 1;
}

ajax '/ajax/control/admin/pseudodevice/add' => require_role admin => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('Device')
        ->create({
          ip => param('ip'),
          dns => param('dns'),
          vendor => 'netdisco',
          last_discover => \'now()',
        });
      return unless $device;

      $device->ports->populate([
        [qw/port type/],
        map {["Port$_", 'other']} @{[1 .. param('ports')]},
      ]);

      # device_ip table is used to show whether topo is "broken"
      schema('netdisco')->resultset('DeviceIp')
        ->create({
          ip => param('ip'),
          alias => param('ip'),
        });
    });
};

ajax '/ajax/control/admin/pseudodevice/del' => require_role admin => sub {
    send_error('Bad Request', 400) unless _sanity_ok();
    forward '/ajax/control/admin/delete', { device => param('ip') };
};

ajax '/ajax/control/admin/pseudodevice/update' => require_role admin => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('Device')
        ->with_port_count->find({ip => param('ip')});
      return unless $device;
      my $count = $device->port_count;

      if (param('ports') > $count) {
          my $start = $count + 1;
          $device->ports->populate([
            [qw/port type/],
            map {["Port$_", 'other']} @{[$start .. param('ports')]},
          ]);
      }
      elsif (param('ports') < $count) {
          my $start = param('ports') + 1;
          $device->ports
            ->single({port => "Port$_"})->delete
          for ($start .. $count);
      }
    });
};

ajax '/ajax/content/admin/pseudodevice' => require_role admin => sub {
    my $set = schema('netdisco')->resultset('Device')
      ->search(
        {vendor => 'netdisco'},
        {order_by => { -desc => 'last_discover' }},
      )->with_port_count;

    content_type('text/html');
    template 'ajax/admintask/pseudodevice.tt', {
      results => $set,
    }, { layout => undef };
};

true;
