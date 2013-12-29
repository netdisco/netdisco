package App::Netdisco::Web::PortControl;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

ajax '/ajax/portcontrol' => require_role port_control => sub {
    send_error('No device/port/field', 400)
      unless param('device') and (param('port') or param('field'));

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

    my $action = $action_map{ param('field') };
    my $subaction = ($action =~ m/^(?:power|portcontrol)/
      ? (param('action') ."-other")
      : param('value'));

    schema('netdisco')->txn_do(sub {
      if (param('port')) {
          my $a = "$action $subaction";
          $a =~ s/-other$//;
          $a =~ s/^portcontrol/port/;

          schema('netdisco')->resultset('DevicePortLog')->create({
            ip => param('device'),
            port => param('port'),
            action => $a,
            username => session('logged_in_user'),
            userip => request->remote_address,
            reason => (param('reason') || 'other'),
            log => param('log'),
          });
      }

      schema('netdisco')->resultset('Admin')->create({
        device => param('device'),
        port => param('port'),
        action => $action,
        subaction => $subaction,
        status => 'queued',
        username => session('logged_in_user'),
        userip => request->remote_address,
        log => $log,
      });
    });

    content_type('application/json');
    to_json({});
};

ajax '/ajax/userlog' => require_login sub {
    my $rs = schema('netdisco')->resultset('Admin')->search({
      username => session('logged_in_user'),
      action => [qw/location contact portcontrol portname vlan power
        discover macsuck arpnip/],
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
