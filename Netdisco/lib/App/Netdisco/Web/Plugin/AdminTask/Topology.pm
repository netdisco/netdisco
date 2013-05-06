package App::Netdisco::Web::Plugin::AdminTask::Topology;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;
use Try::Tiny;

register_admin_task({
  tag => 'topology',
  label => 'Manual Device Topology',
});

sub _sanity_ok {
    my $happy = 0;

    try {
        return 0 unless var('user')->admin;

        return 0 unless length param('dns')
          and param('dns') =~ m/^[[:print:]]+$/
          and param('dns') !~ m/[[:space:]]/;

        my $ip = NetAddr::IP::Lite->new(param('ip'));
        return 0 if $ip->addr eq '0.0.0.0';

        return 0 unless length param('ports')
          and param('ports') =~ m/^[[:digit:]]+$/;

        $happy = 1;
    };

    return $happy;
}

ajax '/ajax/content/admin/topology/add' => sub {
    forward '/ajax/content/admin/topology'
      unless _sanity_ok();

    try {
        schema('netdisco')->txn_do(sub {
          my $device = schema('netdisco')->resultset('Device')
            ->create({
              ip => param('ip'),
              dns => param('dns'),
              vendor => 'netdisco',
              last_discover => \'now()',
            });

          $device->ports->populate([
            ['port'],
            map {["Port$_"]} @{[1 .. param('ports')]},
          ]);
        });
    };

    forward '/ajax/content/admin/topology';
};

ajax '/ajax/content/admin/topology/del' => sub {
    forward '/ajax/content/admin/topology'
      unless _sanity_ok();

    try {
        schema('netdisco')->txn_do(sub {
          my $device = schema('netdisco')->resultset('Device')
            ->find({ip => param('ip')});

          $device->ports->delete;
          $device->delete;
        });
    };

    forward '/ajax/content/admin/topology';
};

ajax '/ajax/content/admin/topology' => sub {
    return unless var('user')->admin;

    my $set = schema('netdisco')->resultset('Topology')
      ->search({},{order_by => [qw/dev1 dev2 port1/]});

    content_type('text/html');
    template 'ajax/admintask/topology.tt', {
      results => $set,
    }, { layout => undef };
};

true;
