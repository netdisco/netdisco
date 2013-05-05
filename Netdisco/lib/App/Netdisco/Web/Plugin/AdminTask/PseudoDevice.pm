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

ajax '/ajax/content/admin/pseudodevice' => sub {
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
