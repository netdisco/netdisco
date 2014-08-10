package App::Netdisco::Web::AdminTask;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::JobQueue 'jq_insert';

sub add_job {
    my ($action, $device, $subaction) = @_;

    if ($device) {
        $device = NetAddr::IP::Lite->new($device);
        return send_error('Bad device', 400)
          if ! $device or $device->addr eq '0.0.0.0';
    }

    jq_insert({
        ($device ? (device => $device->addr) : ()),
        action => $action,
        ($subaction ? (subaction => $subaction) : ()),
        username => session('logged_in_user'),
        userip => request->remote_address,
    });
}

foreach my $action (@{ setting('job_prio')->{high} },
                    @{ setting('job_prio')->{normal} }) {

    ajax "/ajax/control/admin/$action" => require_role admin => sub {
        add_job($action, param('device'), param('extra'));
    };

    post "/admin/$action" => require_role admin => sub {
        add_job($action, param('device'), param('extra'));
        redirect uri_for('/admin/jobqueue')->path;
    };
}

ajax '/ajax/control/admin/delete' => require_role admin => sub {
    send_error('Missing device', 400) unless param('device');

    my $device = NetAddr::IP::Lite->new(param('device'));
    send_error('Bad device', 400)
      if ! $device or $device->addr eq '0.0.0.0';

    schema('netdisco')->txn_do(sub {
      schema('netdisco')->resultset('UserLog')->create({
        username => session('logged_in_user'),
        userip => request->remote_address,
        event => "Delete device ". $device->addr,
        details => param('log'),
      });

      my $device = schema('netdisco')->resultset('Device')
        ->search({ip => param('device')});

      # will delete everything related too...
      $device->delete({archive_nodes => param('archive')});
    });
};

get '/admin/*' => require_role admin => sub {
    my ($tag) = splat;

    # trick the ajax into working as if this were a tabbed page
    params->{tab} = $tag;

    var(nav => 'admin');
    template 'admintask', {
      task => setting('_admin_tasks')->{ $tag },
    };
};

true;
