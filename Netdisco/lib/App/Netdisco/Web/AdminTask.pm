package App::Netdisco::Web::AdminTask;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use Try::Tiny;

sub add_job {
    my ($jobtype, $device) = @_;

    if ($device) {
        $device = NetAddr::IP::Lite->new($device);
        return send_error('Bad device', 400)
          if ! $device or $device->addr eq '0.0.0.0';
    }

    try {
    # jobs might already be in the queue, so this could die
        schema('netdisco')->resultset('Admin')->create({
          ($device ? (device => $device->addr) : ()),
          action => $jobtype,
          status => 'queued',
          username => session('logged_in_user'),
          userip => request->remote_address,
        });

        if (param('extra') and param('extra') eq 'with-walk') {
            schema('netdisco')->resultset('Admin')->create({
              action => 'macwalk',
              subaction => 'after-discoverall',
              status => 'queued',
              username => session('logged_in_user'),
              userip => request->remote_address,
            });
            schema('netdisco')->resultset('Admin')->create({
              action => 'arpwalk',
              subaction => 'after-discoverall',
              status => 'queued',
              username => session('logged_in_user'),
              userip => request->remote_address,
            });
        }
    };
}

# we have a separate list for jobs needing a device to avoid queueing
# such a job when there's no device param (it could still be duff, tho).
my %jobs = map { $_ => 1} qw/
    discover
    macsuck
    arpnip
/;
my %jobs_all = map {$_ => 1} qw/
    discoverall
    macwalk
    arpwalk
/;

foreach my $jobtype (keys %jobs_all, keys %jobs) {
    ajax "/ajax/control/admin/$jobtype" => require_role admin => sub {
        send_error('Missing device', 400)
          if exists $jobs{$jobtype} and not param('device');

        add_job($jobtype, param('device'));
    };

    post "/admin/$jobtype" => require_role admin => sub {
        send_error('Missing device', 400)
          if exists $jobs{$jobtype} and not param('device');

        add_job($jobtype, param('device'));
        redirect uri_for('/admin/jobqueue')->as_string;
    };
}

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
