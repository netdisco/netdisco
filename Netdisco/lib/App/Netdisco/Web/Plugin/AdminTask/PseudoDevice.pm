package App::Netdisco::Web::Plugin::AdminTask::PseudoDevice;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';
use Try::Tiny;

register_admin_task({
  tag => 'pseudodevice',
  label => 'Manage Pseudo Devices',
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

ajax '/ajax/content/admin/pseudodevice/add' => sub {
    forward '/ajax/content/admin/pseudodevice'
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

    forward '/ajax/content/admin/pseudodevice';
};

ajax '/ajax/content/admin/pseudodevice/del' => sub {
    forward '/ajax/content/admin/pseudodevice'
      unless _sanity_ok();

    try {
        schema('netdisco')->txn_do(sub {
          my $device = schema('netdisco')->resultset('Device')
            ->find({ip => param('ip')});

          $device->ports->delete;
          $device->delete;
        });
    };

    forward '/ajax/content/admin/pseudodevice';
};

ajax '/ajax/content/admin/pseudodevice/update' => sub {
    forward '/ajax/content/admin/pseudodevice'
      unless _sanity_ok();

    try {
        schema('netdisco')->txn_do(sub {
          my $device = schema('netdisco')->resultset('Device')
            ->with_port_count->find({ip => param('ip')});
          my $count = $device->port_count;

          if (param('ports') > $count) {
              my $start = $count + 1;
              try {
                  schema('netdisco')->txn_do(sub {
                    $device->ports->populate([
                      ['port'],
                      map {["Port$_"]} @{[$start .. param('ports')]},
                    ]);
                  });
              };
          }
          elsif (param('ports') < $count) {
              my $start = param('ports') + 1;
              try {
                  schema('netdisco')->txn_do(sub {
                    $device->ports
                      ->single({port => "Port$_"})->delete
                    for ($start .. $count);
                  });
              };
          }
        });
    };

    forward '/ajax/content/admin/pseudodevice';
};

ajax '/ajax/content/admin/pseudodevice' => sub {
    return unless var('user')->admin;

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
