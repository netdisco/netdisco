package App::Netdisco::Web::AdminTask;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

sub add_discover_job {
    my $ip = NetAddr::IP::Lite->new(shift);
    return unless $ip
      and $ip->addr ne '0.0.0.0';

    schema('netdisco')->resultset('Admin')->create({
      device => $ip->addr,
      action => 'discover',
      status => 'queued',
      username => session('user'),
      userip => request->remote_address,
    });
}

ajax '/ajax/control/admin/discover' => sub {
    return unless var('user') and var('user')->admin;
    add_discover_job(param('device'));
};

post '/admin/discover' => sub {
    return unless var('user') and var('user')->admin;
    add_discover_job(param('device'));

    status(302);
    header(Location => uri_for('/admin/jobqueue')->path_query());
};

get '/admin/*' => sub {
    my ($tag) = splat;

    if (! var('user')->admin) {
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
