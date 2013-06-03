package App::Netdisco::Web::Plugin::AdminTask::Topology;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';

register_admin_task({
  tag => 'topology',
  label => 'Manual Device Topology',
});

sub _sanity_ok {
    return 0 unless var('user') and var('user')->admin;

    my $dev1 = NetAddr::IP::Lite->new(param('dev1'));
    return 0 unless ($dev1 and $dev1->addr ne '0.0.0.0');

    my $dev2 = NetAddr::IP::Lite->new(param('dev2'));
    return 0 unless ($dev2 and $dev2->addr ne '0.0.0.0');

    return 0 unless length param('port1');
    return 0 unless length param('port2');

    return 1;
}

ajax '/ajax/control/admin/topology/add' => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    my $device = schema('netdisco')->resultset('Topology')
      ->create({
        dev1  => param('dev1'),
        port1 => param('port1'),
        dev2  => param('dev2'),
        port2 => param('port2'),
      });

    # re-set remote device details in affected ports
    # could fail for bad device or port names
    try {
        schema('netdisco')->txn_do(sub {
          # only work on root_ips
          my $left  = get_device(param('dev1'));
          my $right = get_device(param('dev2'));

          # skip bad entries
          return unless ($left->in_storage and $right->in_storage);

          $left->ports
            ->single({port => param('port1')}, {for => 'update'})
            ->update({
              remote_ip => param('dev2'),
              remote_port => param('port2'),
              remote_type => undef,
              remote_id   => undef,
              is_uplink   => \"true",
              manual_topo => \"true",
            });

          $right->ports
            ->single({port => param('port2')}, {for => 'update'})
            ->update({
              remote_ip => param('dev1'),
              remote_port => param('port1'),
              remote_type => undef,
              remote_id   => undef,
              is_uplink   => \"true",
              manual_topo => \"true",
            });
        });
    };
};

ajax '/ajax/control/admin/topology/del' => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('Topology')
        ->search({
          dev1  => param('dev1'),
          port1 => param('port1'),
          dev2  => param('dev2'),
          port2 => param('port2'),
        })->delete;
    });
};

ajax '/ajax/content/admin/topology' => sub {
    send_error('Forbidden', 403) unless var('user')->admin;

    my $set = schema('netdisco')->resultset('Topology')
      ->search({},{order_by => [qw/dev1 dev2 port1/]});

    content_type('text/html');
    template 'ajax/admintask/topology.tt', {
      results => $set,
    }, { layout => undef };
};

true;
