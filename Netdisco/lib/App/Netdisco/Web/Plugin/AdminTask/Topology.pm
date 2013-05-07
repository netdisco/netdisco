package App::Netdisco::Web::Plugin::AdminTask::Topology;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';
use Try::Tiny;

register_admin_task({
  tag => 'topology',
  label => 'Manual Device Topology',
});

sub _sanity_ok {
    my $happy = 0;

    try {
        return 0 unless var('user')->admin;

        my $dev1 = NetAddr::IP::Lite->new(param('dev1'));
        return 0 if $dev1->addr eq '0.0.0.0';

        my $dev2 = NetAddr::IP::Lite->new(param('dev2'));
        return 0 if $dev2->addr eq '0.0.0.0';

        return 0 unless length param('port1');
        return 0 unless length param('port2');

        $happy = 1;
    };

    return $happy;
}

ajax '/ajax/content/admin/topology/add' => sub {
    forward '/ajax/content/admin/topology'
      unless _sanity_ok();

    try {
        my $device = schema('netdisco')->resultset('Topology')
          ->create({
            dev1  => param('dev1'),
            port1 => param('port1'),
            dev2  => param('dev2'),
            port2 => param('port2'),
          });
    };

    forward '/ajax/content/admin/topology';
};

ajax '/ajax/content/admin/topology/del' => sub {
    forward '/ajax/content/admin/topology'
      unless _sanity_ok();

    try {
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
