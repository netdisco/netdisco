package App::Netdisco::Web::Plugin::AdminTask::PseudoDevice;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::DNS 'hostname_from_ip';
use App::Netdisco::Util::Statistics 'pretty_version';
use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';

register_admin_task({
  tag => 'pseudodevice',
  label => 'Pseudo Devices',
});

sub _sanity_ok {
    return 0 unless param('name')
      and param('name') =~ m/^[[:print:]]+$/
      and param('name') !~ m/[[:space:]]/;

    my $ip = NetAddr::IP::Lite->new(param('ip'));
    return 0 unless ($ip and $ip->addr ne '0.0.0.0');

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
          dns => (hostname_from_ip(param('ip')) || ''),
          name => param('name'),
          vendor => 'netdisco',
          model => 'pseudodevice',
          num_ports => param('ports'),
          os => 'netdisco',
          os_ver => pretty_version($App::Netdisco::VERSION, 3),
          layers => param('layers'),
          last_discover => \'now()',
          is_pseudo => \'true',
        });
      return unless $device;

      $device->ports->populate([
        [qw/port type descr/],
        map {["Port$_", 'other', "Port$_"]} @{[1 .. param('ports')]},
      ]);

      # device_ip table is used to show whether topo is "broken"
      schema('netdisco')->resultset('DeviceIp')
        ->create({
          ip => param('ip'),
          alias => param('ip'),
        });
    });
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
            [qw/port type descr/],
            map {["Port$_", 'other', "Port$_"]} @{[$start .. param('ports')]},
          ]);
      }
      elsif (param('ports') < $count) {
          my $start = param('ports') + 1;

          foreach my $port ($start .. $count) {
              $device->ports
                ->single({port => "Port${port}"})->delete;

              # clear outdated manual topology links
              schema('netdisco')->resultset('Topology')->search({
                -or => [
                  { dev1 => $device->ip, port1 => "Port${port}" },
                  { dev2 => $device->ip, port2 => "Port${port}" },
                ],
              })->delete;
          }
      }
      $device->update({num_ports => param('ports')});

      # also set layers
      $device->update({layers => param('layers')});

      # and update last_discover, since device properties changed
      $device->update({last_discover => \'now()'});
    });
};

ajax '/ajax/content/admin/pseudodevice' => require_role admin => sub {
    my $set = schema('netdisco')->resultset('Device')
      ->search(
        {-bool => 'is_pseudo'},
        {order_by => { -desc => 'last_discover' }},
      )->with_port_count;

    content_type('text/html');
    template 'ajax/admintask/pseudodevice.tt', {
      results => $set,
    }, { layout => undef };
};

true;
