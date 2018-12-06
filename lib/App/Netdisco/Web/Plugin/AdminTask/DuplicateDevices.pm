package App::Netdisco::Web::Plugin::AdminTask::DuplicateDevices;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_admin_task({
  tag => 'duplicatedevices',
  label => 'Duplicate Devices',
});

ajax '/ajax/content/admin/duplicatedevices' => require_role admin => sub {
    my @set = schema('netdisco')->resultset('Device')->search({
      serial => { '-in' => schema('netdisco')->resultset('Device')->search({
          '-and' => [serial => { '!=', undef }, serial => { '!=', '' }],
        }, {
          group_by => ['serial'],
          having => \'count(*) > 1',
          columns => 'serial',
        })->as_query
      },
    }, { columns => [qw/ip dns contact location name model os_ver serial/] })
      ->with_times->hri->all;

    content_type('text/html');
    template 'ajax/admintask/duplicatedevices.tt', {
      results => \@set
    }, { layout => undef };
};

true;
