package App::Netdisco::Web::Plugin::AdminTask::PollerPerformance;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

register_admin_task({
  tag => 'performance',
  label => 'Poller Performance',
});

ajax '/ajax/content/admin/performance' => require_role admin => sub {
    my $set = schema('netdisco')->resultset('Admin')
      ->search({
        action => { -in => [qw/discover macsuck arpnip/] },
      }, {
        columns => [
          'action', 'entered',
          { entered_stamp => \"to_char(entered, 'YYYY-MM-DD HH24:MI:SS')" },
        ],
        select => [
          { count => 'device', -as => 'number' },
          { min => 'started',  -as => 'start' },
          { max => 'finished', -as => 'end' },
          \"justify_interval(extract(epoch from (max(finished) - min(started))) * interval '1 second') AS elapsed",
        ],
        as => [qw/ number start end elapsed /],
        group_by => [qw/ action entered /],
        having => \'count(device) > 1',
        order_by => { -desc => [qw/ entered elapsed /] },
        rows => 50,
      });

    content_type('text/html');
    template 'ajax/admintask/performance.tt', {
      results => $set,
    }, { layout => undef };
};

true;
