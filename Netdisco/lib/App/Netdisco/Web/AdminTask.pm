package App::Netdisco::Web::AdminTask;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

sub add_job {
    my ($jobtype, $device) = @_;

    if ($device) {
        $device = NetAddr::IP::Lite->new($device);
        return unless $device
          and $device->addr ne '0.0.0.0';
    }

    schema('netdisco')->resultset('Admin')->create({
      ($device ? (device => $device->addr) : ()),
      action => $jobtype,
      status => 'queued',
      username => session('user'),
      userip => request->remote_address,
    });
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
    ajax "/ajax/control/admin/$jobtype" => sub {
        return unless var('user') and var('user')->admin;
        return if exists $jobs{$jobtype} and not param('device');
        add_job($jobtype, param('device'));
    };

    post "/admin/$jobtype" => sub {
        return unless var('user') and var('user')->admin;
        return if exists $jobs{$jobtype} and not param('device');
        add_job($jobtype, param('device'));

        status(302);
        header(Location => uri_for('/admin/jobqueue')->path_query());
    };
}

get '/admin/*' => sub {
    my ($tag) = splat;

    if (! eval { var('user')->admin }) {
        status(302);
        header(Location => uri_for('/')->path_query());
        return;
    }

    # trick the ajax into working as if this were a tabbed page
    params->{tab} = $tag;

    var(nav => 'admin');
    template 'admintask', {
      task => setting('admin_tasks')->{ $tag },
    };
};

true;
