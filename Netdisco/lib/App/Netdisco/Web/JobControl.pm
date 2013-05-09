package App::Netdisco::Web::JobControl;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

post '/admin/discover' => sub {
    return unless var('user') and var('user')->admin;

    my $ip = NetAddr::IP::Lite->new(param('device'));
    return unless $ip
      and $ip->addr ne '0.0.0.0';

    schema('netdisco')->resultset('Admin')->create({
      device => $ip->addr,
      action => 'discover',
      status => 'queued',
      username => session('user'),
      userip => request->remote_address,
    });

    status(302);
    header(Location => uri_for('/admin/jobqueue')->path_query());
};

true;
