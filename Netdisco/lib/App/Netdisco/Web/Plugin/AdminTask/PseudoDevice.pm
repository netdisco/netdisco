package App::Netdisco::Web::Plugin::AdminTask::PseudoDevice;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

use App::Netdisco::Web::Plugin;

register_admin_task({
  tag => 'pseudodevice',
  label => 'Manage Pseudo Devices',
});

ajax '/ajax/content/admin/pseudodevice' => sub {
    my $set = schema('netdisco')->resultset('Device')
      ->search(
        {vendor => 'netdisco'},
        {order_by => { -desc => 'last_discover' }},
      );

    content_type('text/html');
    template 'ajax/admintask/pseudodevice.tt', {
      results => $set,
    }, { layout => undef };
};

true;
