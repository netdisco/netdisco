package App::Netdisco::Web::PortControl;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;

ajax '/ajax/portcontrol' => sub {
    send_error('Forbidden', 403)
      unless var('user')->port_control;
    send_error('No device/port/field', 400)
      unless param('device') and param('port') and param('field');

    my $log = sprintf 'd:[%s] p:[%s] f:[%s]. a:[%s] v[%s]',
      param('device'), (param('port') || ''), param('field'),
      (param('action') || ''), (param('value') || '');

    my %action_map = (
      'location' => 'location',
      'contact'  => 'contact',
      'c_port'   => 'portcontrol',
      'c_name'   => 'portname',
      'c_vlan'   => 'vlan',
      'c_power'  => 'power',
    );

    send_error('No action/value', 400)
      unless (param('action') or param('value'));

    my $action = $action_map{ param('field') };
    my $subaction = ($action =~ m/^(?:power|portcontrol)/
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

    content_type('application/json');
    to_json({});
};

ajax '/ajax/userlog' => sub {
    my $user = session('user');
    send_error('No username', 400) unless $user;

    my $rs = schema('netdisco')->resultset('Admin')->search({
      username => $user,
      action => [qw/location contact portcontrol portname vlan power/],
      finished => { '>' => \"(now() - interval '5 seconds')" },
    });

    my %status = (
      'done'  => [
        map {s/\[\]/&lt;empty&gt;/; $_}
        $rs->search({status => 'done'})->get_column('log')->all
      ],
      'error' => [
        map {s/\[\]/&lt;empty&gt;/; $_}
        $rs->search({status => 'error'})->get_column('log')->all
      ],
    );

    content_type('application/json');
    to_json(\%status);
};

true;
