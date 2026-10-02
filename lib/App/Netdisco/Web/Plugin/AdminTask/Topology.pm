package App::Netdisco::Web::Plugin::AdminTask::Topology;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Port qw/port_acl_check port_acl_by_role_check sync_portctl_roles/;

use Try::Tiny;
use NetAddr::IP::Lite ':lower';

register_admin_task({
  tag => 'topology',
  label => 'Manual Device Topology',
  roles => [qw/admin port_control/],
});

sub _sanity_ok {
    my $dev1 = NetAddr::IP::Lite->new(param('dev1'));
    return 0 unless ($dev1 and $dev1->addr ne '0.0.0.0');

    my $dev2 = NetAddr::IP::Lite->new(param('dev2'));
    return 0 unless ($dev2 and $dev2->addr ne '0.0.0.0');

    return 0 unless param('port1');
    return 0 unless param('port2');

    return 0 if
      (($dev1->addr eq $dev2->addr) and (param('port1') eq param('port2')));

    return 1;
}

# These routes write is_uplink and the remote_* columns on a named port, which
# is a port change like any other, so they answer to the same role ACL. The
# service check is not used: it refuses a port that is already an uplink, which
# is what manual topology exists to set.
sub _scope_ok {
    my ($ip, $portname) = @_;
    return 1 if user_has_role('admin');

    # the database half of portctl_by_role is only in scope once this has run,
    # which is why every port control worker calls it before its own check
    sync_portctl_roles();

    my $device = get_device($ip);
    return 0 unless $device and $device->in_storage;
    my $port = $device->ports->search({ 'me.port' => $portname })->single
      or return 0;

    return 0 unless port_acl_check($port, $device, logged_in_user);
    return port_acl_by_role_check($port, $device, logged_in_user) ? 1 : 0;
}

ajax '/ajax/control/admin/topology/add' => require_any_role [qw(admin port_control)] => sub {
    send_error('Bad Request', 400) unless _sanity_ok();
    send_error('Forbidden', 403)
      unless _scope_ok(param('dev1'), param('port1'))
         and _scope_ok(param('dev2'), param('port2'));

    my $device = schema(vars->{'tenant'})->resultset('Topology')
      ->create({
        dev1  => param('dev1'),
        port1 => param('port1'),
        dev2  => param('dev2'),
        port2 => param('port2'),
      });

    # re-set remote device details in affected ports
    # could fail for bad device or port names
    try {
        schema(vars->{'tenant'})->txn_do(sub {
          # only work on root_ips
          my $left  = get_device(param('dev1'));
          my $right = get_device(param('dev2'));

          # skip bad entries
          return unless ($left->in_storage and $right->in_storage);

          $left->ports
            ->search({port => param('port1')}, {for => 'update'})
            ->single()
            ->update({
              remote_ip   => param('dev2'),
              remote_port => param('port2'),
              remote_type => undef,
              remote_id   => undef,
              is_uplink   => \"true",
              manual_topo => \"true",
            });

          $right->ports
            ->search({port => param('port2')}, {for => 'update'})
            ->single()
            ->update({
              remote_ip   => param('dev1'),
              remote_port => param('port1'),
              remote_type => undef,
              remote_id   => undef,
              is_uplink   => \"true",
              manual_topo => \"true",
            });
        });
    };

    return '';
};

ajax '/ajax/control/admin/topology/del' => require_any_role [qw(admin port_control)] => sub {
    send_error('Bad Request', 400) unless _sanity_ok();
    send_error('Forbidden', 403)
      unless _scope_ok(param('dev1'), param('port1'))
         and _scope_ok(param('dev2'), param('port2'));

    schema(vars->{'tenant'})->txn_do(sub {
      my $device = schema(vars->{'tenant'})->resultset('Topology')
        ->search({
          dev1  => param('dev1'),
          port1 => param('port1'),
          dev2  => param('dev2'),
          port2 => param('port2'),
        })->delete;
    });

    # re-set remote device details in affected ports
    # could fail for bad device or port names
    try {
        schema(vars->{'tenant'})->txn_do(sub {
          # only work on root_ips
          my $left  = get_device(param('dev1'));
          my $right = get_device(param('dev2'));

          # skip bad entries
          return unless ($left->in_storage and $right->in_storage);

          $left->ports
            ->search({port => param('port1')}, {for => 'update'})
            ->single()
            ->update({
              remote_ip   => undef,
              remote_port => undef,
              remote_type => undef,
              remote_id   => undef,
              is_uplink   => \"false",
              manual_topo => \"false",
            });

          $right->ports
            ->search({port => param('port2')}, {for => 'update'})
            ->single()
            ->update({
              remote_ip   => undef,
              remote_port => undef,
              remote_type => undef,
              remote_id   => undef,
              is_uplink   => \"false",
              manual_topo => \"false",
            });
        });
    };

    return '';
};

ajax '/ajax/content/admin/topology' => require_any_role [qw(admin port_control)] => sub {
    my $set = schema(vars->{'tenant'})->resultset('Topology')
      ->search({},{order_by => [qw/dev1 dev2 port1/]});

    content_type('text/html');
    template 'ajax/admintask/topology.tt', {
      results => $set,
    }, { layout => undef };
};

true;
