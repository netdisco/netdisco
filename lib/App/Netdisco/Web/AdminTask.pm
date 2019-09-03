package App::Netdisco::Web::AdminTask;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use NetAddr::IP qw/:rfc3021 :lower/;
use App::Netdisco::JobQueue 'jq_insert';
use App::Netdisco::Util::Device 'delete_device';

sub add_job {
    my ($action, $device, $subaction) = @_;

    my $net = NetAddr::IP->new($device);
    return if
      ($device and (!$net or $net->num == 0 or $net->addr eq '0.0.0.0'));

    my @hostlist = $device ? ($net->hostenum) : (undef);

    jq_insert([map {{
      ($_ ? (device => $_->addr) : ()),
      action => $action,
      ($subaction ? (subaction => $subaction) : ()),
      username => session('logged_in_user'),
      userip => request->remote_address,
    }} @hostlist]);

    true;
}

foreach my $action (@{ setting('job_prio')->{high} },
                    @{ setting('job_prio')->{normal} }) {

    ajax "/ajax/control/admin/$action" => require_role admin => sub {
        add_job($action, param('device'), param('extra'))
          or send_error('Bad device', 400);
    };

    post "/admin/$action" => require_role admin => sub {
        add_job($action, param('device'), param('extra'))
          ? redirect uri_for('/admin/jobqueue')->path
          : redirect uri_for('/')->path;
    };
}

ajax qr{/ajax/control/admin/(?:\w+/)?delete} => require_role setting('defanged_admin') => sub {
    send_error('Missing device', 400) unless param('device');

    my $device = NetAddr::IP->new(param('device'));
    send_error('Bad device', 400)
      if ! $device or $device->addr eq '0.0.0.0';

    return delete_device(
      $device->addr, param('archive'), param('log'),
    );
};

get '/admin/*' => require_role admin => sub {
    my ($tag) = splat;

    if (exists setting('_admin_tasks')->{ $tag }) {
      # trick the ajax into working as if this were a tabbed page
      params->{tab} = $tag;

      var(nav => 'admin');
      template 'admintask', {
        task => setting('_admin_tasks')->{ $tag },
      };
    }
    else {
      var('notfound' => true);
      status 'not_found';
      template 'index';
    }
};

true;
