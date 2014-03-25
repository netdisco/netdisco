package App::Netdisco::Web::AdminTask;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use Try::Tiny;

# we have a separate list for jobs needing a device to avoid queueing
# such a job when there's no device param (it could still be duff, tho).
my %jobs = map { $_ => 1} qw/
    discover
    macsuck
    arpnip
    nbtstat
/;
my %jobs_all = map {$_ => 1} qw/
    discoverall
    macwalk
    arpwalk
    nbtwalk
/;

sub add_job {
    my ($jobtype, $device, $subaction) = @_;

    if ($device) {
        $device = NetAddr::IP::Lite->new($device);
        return send_error('Bad device', 400)
          if ! $device or $device->addr eq '0.0.0.0';
    }

    # job might already be in the queue, so this could die
    try {
        schema('netdisco')->resultset('Admin')->create({
          ($device ? (device => $device->addr) : ()),
          action => $jobtype,
          ($subaction ? (subaction => $subaction) : ()),
          status => 'queued',
          (exists $jobs{$jobtype} ? (username => session('logged_in_user')) : ()),
          userip => request->remote_address,
        });
    };
}

foreach my $jobtype (keys %jobs_all, keys %jobs) {
    ajax "/ajax/control/admin/$jobtype" => require_role admin => sub {
        send_error('Missing device', 400)
          if exists $jobs{$jobtype} and not param('device');

        add_job($jobtype, param('device'), param('extra'));
    };

    post "/admin/$jobtype" => require_role admin => sub {
        send_error('Missing device', 400)
          if exists $jobs{$jobtype} and not param('device');

        add_job($jobtype, param('device'), param('extra'));
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
