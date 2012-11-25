package Netdisco::Web::PortControl;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Try::Tiny;

ajax '/ajax/portcontrol' => sub {
    try {
        my $log = sprintf 'd:[%s] p:[%s] f:[%s]. a:[%s] v[%s]',
          param('device'), (param('port') || ''), param('field'),
          (param('action') || ''), (param('value') || '');

        my %action_map = (
            'location' => 'location',
            'contact'  => 'contact',
            'c_port'   => 'portcontrol',
            'c_name'   => 'portname',
            'c_vlan'   => 'vlan',
        );

        my $action = $action_map{ param('field') };
        my $subaction = ($action eq 'portcontrol'
          ? (param('action') ."-other")
          : param('value'));

        schema('netdisco')->resultset('Admin')->create({
            device => param('device'),
            port => param('port'),
            action => $action,
            subaction => $subaction,
            status => 'queued',
            username => session('user'),
            userip => request->remote_address,
            log => $log,
        });
    }
    catch {
        send_error('Failed to parse params or add DB record');
    };

    content_type('application/json');
    to_json({});
};

ajax '/ajax/userlog' => sub {
    my $user = session('user');
    send_error('No username') unless $user;

    my $rs = schema('netdisco')->resultset('Admin')->search({
      username => $user,
      action => [qw/portcontrol vlan location/],
      finished => { '>' => \"(now() - interval '5 seconds')" },
    });

    my %status = (
        'done'  => $rs->search({status => 'done'})->count(),
        'error' => $rs->search({status => 'error'})->count(),
    );

    content_type('application/json');
    to_json(\%status);
};

true;
