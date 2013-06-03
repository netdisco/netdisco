package App::Netdisco::Web::Plugin::AdminTask::PseudoDevice;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';

register_admin_task({
  tag => 'pseudodevice',
  label => 'Pseudo Devices',
});

sub _sanity_ok {
    return 0 unless var('user') and var('user')->admin;

    return 0 unless length param('dns')
      and param('dns') =~ m/^[[:print:]]+$/
      and param('dns') !~ m/[[:space:]]/;

    my $ip = NetAddr::IP::Lite->new(param('ip'));
    return 0 unless ($ip and$ip->addr ne '0.0.0.0');

    return 0 unless length param('ports')
      and param('ports') =~ m/^[[:digit:]]+$/;

    return 1;
}

ajax '/ajax/control/admin/pseudodevice/add' => sub {
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
        ['port'],
        map {["Port$_"]} @{[1 .. param('ports')]},
      ]);
    });
};

ajax '/ajax/control/admin/pseudodevice/del' => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('Device')
        ->find({ip => param('ip')});

      $device->ports->delete;
      $device->delete;
    });
};

ajax '/ajax/control/admin/pseudodevice/update' => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('Device')
        ->with_port_count->find({ip => param('ip')});
      return unless $device;
      my $count = $device->port_count;

      if (param('ports') > $count) {
          my $start = $count + 1;
          $device->ports->populate([
            ['port'],
            map {["Port$_"]} @{[$start .. param('ports')]},
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

ajax '/ajax/content/admin/pseudodevice' => sub {
    send_error('Forbidden', 403) unless var('user')->admin;

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
