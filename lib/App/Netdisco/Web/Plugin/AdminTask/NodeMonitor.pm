package App::Netdisco::Web::Plugin::AdminTask::NodeMonitor;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Node 'check_mac';

register_admin_task({
  tag => 'nodemonitor',
  label => 'Node Monitor',
});

sub _sanity_ok {
    return 0 unless param('mac')
      and check_mac(param('mac'));

    params->{mac} = check_mac(param('mac'));
    return 1;
}

ajax '/ajax/control/admin/nodemonitor/add' => require_role admin => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema(vars->{'tenant'})->txn_do(sub {
      my $monitor = schema(vars->{'tenant'})->resultset('NodeMonitor')
        ->create({
          mac => param('mac'),
          matchoui => (param('matchoui') ? \'true' : \'false'),
          active => (param('active') ? \'true' : \'false'),
          why => param('why'),
          cc => param('cc'),
        });
    });
};

ajax '/ajax/control/admin/nodemonitor/del' => require_role admin => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema(vars->{'tenant'})->txn_do(sub {
      schema(vars->{'tenant'})->resultset('NodeMonitor')
        ->find({mac => param('mac')})->delete;
    });
};

ajax '/ajax/control/admin/nodemonitor/update' => require_role admin => sub {
    send_error('Bad Request', 400) unless _sanity_ok();

    schema(vars->{'tenant'})->txn_do(sub {
      my $monitor = schema(vars->{'tenant'})->resultset('NodeMonitor')
        ->find({mac => param('mac')});
      return unless $monitor;

      $monitor->update({
        mac => param('mac'),
        matchoui => (param('matchoui') ? \'true' : \'false'),
        active => (param('active') ? \'true' : \'false'),
        why => param('why'),
        cc => param('cc'),
        date => \'LOCALTIMESTAMP',
      });
    });
};

ajax '/ajax/content/admin/nodemonitor' => require_role admin => sub {
    my $set = schema(vars->{'tenant'})->resultset('NodeMonitor')
      ->search(undef, { order_by => [qw/active date mac/] });

    content_type('text/html');
    template 'ajax/admintask/nodemonitor.tt', {
      results => $set,
    }, { layout => undef };
};

true;
